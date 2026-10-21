#!/bin/bash

OPENOCD_PATH="C:/Infineon/Tools/ModusToolboxProgtools-vx.y/openocd"

usage() {
    echo "Usage: sh scripts/extract_iat_iak_pkey.sh <TARGET> <SILICON_REVISION>"
    echo "  <TARGET>            EPC2 or EPC4"
    echo "  <SILICON_REVISION>  B0 or B1"
    echo "Example: sh scripts/extract_iat_iak_pkey.sh EPC2 B0"
}

if [ "$#" -ne 2 ]; then
    echo "ERROR: Invalid number of arguments."
    usage
    exit 1
fi

TARGET="$(echo "$1" | tr '[:lower:]' '[:upper:]')"
SILICON_REVISION="$(echo "$2" | tr '[:lower:]' '[:upper:]')"

# Device variant used by openocd/edgeprotecttools configs:
#   s2 -> EPC2 targets (KIT_PSE84_EVAL_EPC2)
#   s4 -> EPC4 targets (KIT_PSE84_EVAL_EPC4)
case "${TARGET}" in
    EPC2) DEVICE_VARIANT="s2" ;;
    EPC4) DEVICE_VARIANT="s4" ;;
    *)
        echo "ERROR: Invalid target '$1'. Expected EPC2 or EPC4."
        usage
        exit 1
        ;;
esac

# B0 silicon needs an explicit '--rev B0'; B1 is the default revision.
case "${SILICON_REVISION}" in
    B0) REV_OPTION="--rev B0" ;;
    B1) REV_OPTION="" ;;
    *)
        echo "ERROR: Invalid silicon revision '$2'. Expected B0 or B1."
        usage
        exit 1
        ;;
esac

echo "Using target: ${TARGET} (device variant: ${DEVICE_VARIANT}, silicon revision: ${SILICON_REVISION})"

echo "Extracting Initial Attestation token from SRAM1 shared memory..."
echo "openocd logs stored in openocd_logs.txt"
${OPENOCD_PATH}/bin/openocd.exe -s ../scripts -f interface/kitprog3.cfg -f target/infineon/pse84xgx${DEVICE_VARIANT}.cfg -c "init; reset init; dump_image ./Attestation_token.cbor 0x240fe000 1024; shutdown" &>openocd_logs.txt
echo "Attestation Token extracted. Token stored in Attestation_token.cbor"

echo "Extracting Alias Certificate from device..."
echo "Edgeprotectools logs stored in edgeprotecttools_cert_logs.txt"
edgeprotecttools -t pse8x${DEVICE_VARIANT} ${REV_OPTION} init

edgeprotecttools set-ocd -n openocd -p ${OPENOCD_PATH} -c infineon/pse84xgx${DEVICE_VARIANT}.cfg

edgeprotecttools -t pse84 ${REV_OPTION} integrity-exam --alias-cert alias_cert.cbor &>edgeprotecttools_cert_logs.txt
echo "Alias Certificate extracted. Certificate stored in alias_cert.cbor"

echo "Extracting IAK public key from alias certificate"
IAK_PUB_KEY="$(edgeprotecttools cbor2json -i alias_cert.cbor | grep -i "PUBLIC_KEY_0" | cut -d"'" -f2)"
STR="/\"pub\": /c \  \"pub\": \"${IAK_PUB_KEY}\""
sed -i "${STR}" keys/ec_key_tmpl.json
edgeprotecttools create-key --key-type ECDSA-P256 --template keys/ec_key_tmpl.json --format PEM -o IAK_PUB_KEY.pem
echo "IAK public key extracted. Key stored in IAK_PUB_KEY.pem"