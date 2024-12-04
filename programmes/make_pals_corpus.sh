#!/usr/bin/env bash

# Fail early, fail often.
set -euo pipefail

# Tous nos chemins sont relatifs à la racine du dépôt, on va assurer en les rendant absolus automagiquement...
SCRIPT_NAME="${BASH_SOURCE[0]}"
# On sait que ce script est à un répertoire de profondeur de la racine.
BASE_DIR="$(readlink -f "${SCRIPT_NAME%/*}/..")"

# On préfère certains outils GNU sous macOS...
if [ "$(uname -s)" == "Darwin" ] ; then
	GREP_BIN="ggrep"
else
	GREP_BIN="grep"
fi

# Validation basique du paramètre
if [ $# -ne 1 ] ; then
	>&2 echo "usage: ${0} <langue>"
	exit 1
fi

LANG="${1}"
if [ -z "${LANG}" ] ; then
	>&2 echo "La langue ne peut pas être une chaîne vide."
	exit 1
fi

# Gestion de l'arborescence
LANG="${LANG^^}"
OUTPUT_TXT_REL="dumps-text/${LANG}-*.txt"
OUTPUT_TXT="${BASE_DIR}/${OUTPUT_TXT_REL}"
OUTPUT_CTX_REL="contextes/${LANG}-*.txt"
OUTPUT_CTX="${BASE_DIR}/${OUTPUT_CTX_REL}"

# Tokenization
cat ${OUTPUT_TXT} | ${GREP_BIN} -Po "\b[-\p{l}]+\b"
