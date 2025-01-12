#!/usr/bin/env bash

# Fail early, fail often.
set -euo pipefail

if [ $# -lt 1 ] ; then
	echo "usage: ${0} <fichier> [lignes]"
	exit 1
fi

INPUT="${1}"
LINES="${2:-25}"

SCRIPT_NAME="${BASH_SOURCE[0]}"
SCRIPT_BASE_DIR="$(readlink -f "${SCRIPT_NAME%/*}")"

# On préfère certains outils GNU sous macOS...
if [ "$(uname -s)" == "Darwin" ] ; then
	GREP_BIN="ggrep"
	SED_BIN="gsed"
else
	GREP_BIN="grep"
	SED_BIN="sed"
fi

# Un mot par ligne
# Tout en minuscule
# On double les mots (toujours un par ligne),
# on dégage la première ligne pour éviter le doublon initial et ainsi désynchroniser les paires (i.e., 1 2 -> 2 3 au lieu de 1 1 -> 2 2),
# on laisse paste combiner les paires, une paire par ligne, chaque mot séparé par un espace,
# on dégage la dernière ligne pour éviter le dernier mot orphelin dû à notre désynchro initiale,
# et on trie par fréquence comme dans compt_freq.sh
cat "${INPUT}" |						\
	${GREP_BIN} -Po "\b[-\p{l}]+\b" |	\
	tr "[:upper:]" "[:lower:]" |		\
	${SED_BIN} -re 's/^(.*)$/\1\n\1/' |	\
	${SED_BIN} '1d' |					\
	paste -s -d ' \n' - |				\
	${SED_BIN} '$d' |					\
	sort | uniq -c | sort -nr |			\
	head -n "${LINES}"

# NOTE: Parceque la manpage de paste m'a un peu cassé le cerveau
#       (la manpage GNU est sensiblement plus claire, mais sans exemples, la manpage BSD est plutôt infâme, mais sauvée par les exemples),
#       note pour plus tard:
#       le fonctionnement par défaut ressemble en fait assez à la fonction zip() en Python.
#       (Bon, là, pas vraiment parcequ'avec -s on ne le fait travailler que sur un seul fichier,
#       et on joue avec la circularité des deux caractères de délimitation passés à -d pour faire une paire puis sauter une ligne).
