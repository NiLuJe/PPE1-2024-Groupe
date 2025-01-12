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
	SED_BIN="gsed"
else
	GREP_BIN="grep"
	SED_BIN="sed"
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
OUTPUT_TXT_PAL="${BASE_DIR}/pals/dumps-text-${LANG}.txt"
# NOTE: On ne veut *pas* les bigrammes, qui suivent un schéma "LL-dd-bigram-freq.txt" ;).
OUTPUT_CTX_REL="contextes/${LANG}-??.txt"
OUTPUT_CTX="${BASE_DIR}/${OUTPUT_CTX_REL}"
OUTPUT_CTX_PAL="${BASE_DIR}/pals/contextes-${LANG}.txt"

# Tokenization
>&2 echo "Tokenization des dumps texte en ${LANG}"
# NOTE: C'est plutôt bof la gestion des phrases... (la répétition foireuse c'est pour laisser les middle name US tranquilles, mais ça laisse quand même passer quelques abréviations...)
# TODO: pymorphy2? udpipe? Unitex?
# NOTE: On peut se poser la question de quoi faire avec les apostrophes pour la tokenization...
#       (e.g., on a *beaucoup* de formes p'tit/p'tite dans le corpus FR qui se font dézinguer en deux tokens P + tit(e)...).
#       Mais si on solidarise ce genre de choss, on solidarise aussi tous les articles contractés...
cat ${OUTPUT_TXT} | ${SED_BIN} -re 's/(\w{2,}\b)([.?!])/\1 %EoS%/g' | ${GREP_BIN} -Po "\b[-\p{l}]+\b" | sed "s/EoS//" > "${OUTPUT_TXT_PAL}"

# Rebelotte pour les contextes
>&2 echo "Tokenization des contextes en ${LANG}"
cat ${OUTPUT_CTX} | ${SED_BIN} -re 's/(\w{2,}\b)([.?!])/\1 %EoS%/g' | ${GREP_BIN} -Po "\b[-\p{l}]+\b" | sed "s/EoS//" > "${OUTPUT_CTX_PAL}"
