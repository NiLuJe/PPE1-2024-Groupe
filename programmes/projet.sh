#!/usr/bin/env bash

# Fail early, fail often.
set -euo pipefail
# Debugging
#set -x

# Tous nos chemins sont relatifs à la racine du dépôt, on va assurer en les rendant absolus automagiquement...
SCRIPT_NAME="${BASH_SOURCE[0]}"
# On sait que ce script est à un répertoire de profondeur de la racine.
BASE_DIR="$(readlink -f "${SCRIPT_NAME%/*}/..")"

# TODO: Merge bigram
# FIXME: Gestion des flexions et/ou mots composés (concordancier en particulier?)

# On préfère certains outils GNU sous macOS...
if [ "$(uname -s)" == "Darwin" ] ; then
	UCONV_BIN="/opt/homebrew/opt/icu4c/bin/uconv"
	WC_BIN="gwc"
	SED_BIN="gsed"
else
	UCONV_BIN="uconv"
	WC_BIN="wc"
	SED_BIN="sed"
fi

# Validation basique du paramètre
if [ $# -ne 1 ] ; then
	>&2 echo "usage: ${0} <liste_url>"
	exit 1
fi

INPUT_URL_LIST="${1}"
if [ -z "${INPUT_URL_LIST}" ] ; then
	>&2 echo "La liste d'URLs ne peut pas être une chaîne vide."
	exit 1
fi

# On va aussi vérifier qu'on puisse accéder au fichier, tant qu'à faire
if ! [ -f "${INPUT_URL_LIST}" ] ; then
	>&2 echo "Impossible d'accéder au fichier '${INPUT_URL_LIST}' (problème de chemin?)"
	exit 1
fi
if ! [ -r "${INPUT_URL_LIST}" ] ; then
	>&2 echo "Impossible de lire le fichier '${INPUT_URL_LIST}' (problème de permissions?)"
	exit 1
fi

# On va chopper le code ISO de la langue depuis le nom de fichier
TABLE_LANG="${INPUT_URL_LIST##*/}"	# i.e., basename
TABLE_LANG="${TABLE_LANG%%.*}"		# i.e., strip file extensions
TABLE_LANG="${TABLE_LANG^^}"		# i.e., tr '[:lower:]' '[:upper:]' (mais Bash 4+ only)

# Le mot étudié
declare -a LANG_ARRAY
LANG_ARRAY=(
	"FR"
	"EN"
	"RU"
)
declare -a WORD_ARRAY
WORD_ARRAY=(
	"bébé"
	"baby"
	"Alèd Elisa!"
)
declare -a RE_WORD_ARRAY
# Le motif RE pour chopper les flexions & cie...
RE_WORD_ARRAY=(
	"\<(bébés?)\>"
	"\<(bab(y|ies|es?))\>"
	"Alèd Elisa!"
)
MOT=""
RE_MOT=""

# On va chopper le mot dans la langue de la liste d'URL automagiquement
for i in "${!LANG_ARRAY[@]}" ; do
	lang="${LANG_ARRAY[${i}]}"

	if [ "${lang}" = "${TABLE_LANG}" ] ; then
		MOT="${WORD_ARRAY[${i}]}"
		RE_MOT="${RE_WORD_ARRAY[${i}]}"
	fi
done

if [ -z "${MOT}" ] ; then
	>&2 echo "Impossible de trouver le mot cible dans la langue donnée!"
	exit 1
fi

# Roulez jeunesse (sur stderr pour pa pourrir notre tableau ^^)!
>&2 echo "Traitement du mot ${MOT} en ${TABLE_LANG}"

# On va avoir besoin de s'assurer que notre code HTTP est bien un entier...
is_integer()
{
	# Cheap trick ;)
	[ "${1}" -eq "${1}" ] 2>/dev/null
	return $?
}

## Début du HTML
${SED_BIN} -re "s/%LANG%/${TABLE_LANG}/" "${BASE_DIR}/templates/tableau.head.tpl"

# On passe par un template pour gérer la création de nos concordanciers sans que ça soit *trop* illisible ;p.
# Mais pour que notre template reste humainement lisible,
# on va devoir échapper les tab & LF (et les guillemets) pour que sed comprenne ce qui lui arrive ;p.
CONC_ROW_TEMPLATE="$(${SED_BIN} -e 's/\t/\\t/g' "${BASE_DIR}/templates/concordancier.row.tpl" | ${SED_BIN} -z 's/\n/\\n/g' | ${SED_BIN} 's/"/\\"/g')"

# On va avoir besoin de tenir un compte des lignes parcourues
line_nb=1
while read -r line ; do
	# Si la ligne commence par un #, on passe
	if echo "${line}" | grep -Eq "^#" ; then
		continue
	fi

	# On teste une requête GET via cURL (en suivant les redirections),
	# et on lui demande de nous écrire le code HTTP et la valeur de l'en-tête Content-Type en toute fin de sortie, sur une ligne dédiée.
	file_idx="$(printf "%02d" "${line_nb}")"
	OUTPUT_HTML_REL="aspirations/${TABLE_LANG}-${file_idx}.html"
	OUTPUT_HTML="${BASE_DIR}/${OUTPUT_HTML_REL}"
	OUTPUT_TXT_REL="dumps-text/${TABLE_LANG}-${file_idx}.txt"
	OUTPUT_TXT="${BASE_DIR}/${OUTPUT_TXT_REL}"
	OUTPUT_CTX_REL="contextes/${TABLE_LANG}-${file_idx}.txt"
	OUTPUT_CTX="${BASE_DIR}/${OUTPUT_CTX_REL}"
	OUTPUT_CON_REL="concordances/${TABLE_LANG}-${file_idx}.html"
	OUTPUT_CON="${BASE_DIR}/${OUTPUT_CON_REL}"

	# On va avoir besoin de la sortie de cURL...
	# (curl peut retourner une erreur, donc on va tempérer set -e pour cet appel)
	set +e
	curl_out="$(curl -L -f -w "\n%{http_code}\t%{content_type}\n" -s "${line}" -o "${OUTPUT_HTML}")"
	curl_ret="$?"
	set -e

	# On isole notre chaîne formattée via -w, qui devrait toujours se trouver sur la dernière ligne
	curl_string="$(echo "${curl_out}" | tail -n 1)"
	http_status="$(echo "${curl_string}" | cut -f1)"
	content_type="$(echo "${curl_string}" | cut -f2)"
	# S'il existe, on récupère quand même le charset spécifié dans l'en-tête, pour la forme...
	if echo "${content_type}" | grep -Eq "\bcharset=.*\b" ; then
		page_encoding="$(echo "${content_type}" | grep -Eo "\bcharset=.*\b" | cut -d"=" -f2)"
	else
		page_encoding="N/A"
	fi

	if [ ${curl_ret} -ne 0 ] ; then
		# Si cURL s'est méchamment rétamé, on veut en garder la trace
		is_integer "${http_status}" || http_status="N/A"
	fi

	# On va préferer le charset spécifié dans la page:
	# le charset spécifié par le serveur dans l'en-tête Content-Type est optionel,
	# et souvent peu pertinent (et ce malgré le fait qu'il soit censé avoir la priorité...).
	word_count="N/A"
	status_color="success"
	match_count="0"
	# On va avoir besoin de gratter le code de la page pour ces deux là,
	# ce qui implique qu'on ait bien réussi à récupérer une page (i.e., un code HTTP 2xx)...
	if [ "${http_status}" != "N/A" ] && [ "${http_status}" -ge 200 ] && [ "${http_status}" -lt 300 ] ; then
		# On commence par vérifier si on est pas tombé sur du XHTML pur...
		if head -n 1 "${OUTPUT_HTML}" | grep -Eq "^<\?xml" ; then
			page_encoding="$(head -n 1 "${OUTPUT_HTML}" | ${SED_BIN} -re "s/.*encoding\s*=\s*[\'\"]?([-_:[:alnum:]]+)[\'\"]?.*/\1/")"
		else
			# On va garder le premier (vu que la balise devrait être dans le bloc head)
			# charset= qu'on croise dans le code et croiser les doigts ;p.
			# c.f., https://www.w3.org/International/questions/qa-html-encoding-declarations.var
			#     & https://www.w3schools.com/html/html_charset.asp
			page_encoding="$(grep charset "${OUTPUT_HTML}" | head -n 1 | ${SED_BIN} -re "s/.*charset\s*=\s*[\'\"]?([-_:[:alnum:]]+)[\'\"]?.*/\1/")"
		fi

		# Si la page n'est pas en UTF-8, on convertit
		if [ "${page_encoding^^}" != "UTF-8" ] ; then
			>&2 echo "Transcodage de ${page_encoding^^} vers UTF-8 pour la page ${line}"
			${UCONV_BIN} -f "${page_encoding}" -t "UTF-8" -x Any-NFC --callback escape-unicode "${OUTPUT_HTML}" -o "${OUTPUT_HTML}.uconv"
		else
			# Même si elle est en UTF-8, on la valide & normalise pour assurer les traitements suivants
			# (Normalement, on devrait déjà être en NFC, c.f., https://www.w3.org/TR/charmod-norm/#unicodeNormalization)
			${UCONV_BIN} -t "UTF-8" -x Any-NFC --callback escape-unicode "${OUTPUT_HTML}" -o "${OUTPUT_HTML}.uconv"
			# Si un changement a vraiment été opéré, on va l'indiquer au cas où ça nous joue des tours plus tard...
			if [ "$(md5sum "${OUTPUT_HTML}" | cut -f1 -d" ")" != "$(md5sum "${OUTPUT_HTML}.uconv" | cut -f1 -d" ")" ] ; then
				>&2 echo "Normalisation effectuée pour la page ${line}"
			fi
		fi
		# On garde l'UTF-8 uniquement
		mv "${OUTPUT_HTML}.uconv" "${OUTPUT_HTML}"

		# On va laisser à lynx le job d'interpréter le HTML pour qu'il ne nous reste que le texte
		lynx -display_charset=UTF-8 -dump -nolist "${OUTPUT_HTML}" > "${OUTPUT_TXT}"
		# GNU wc pour éviter l'indentation de BSD wc...
		word_count="$(${WC_BIN} -w "${OUTPUT_TXT}" | cut -f1 -d" ")"

		# Grep retourne un code d'erreur si le mot n'est pas identifié!
		if grep -Eiq "${RE_MOT}" "${OUTPUT_TXT}" ; then
			# On compte le nombre d'occurrences
			match_count="$(grep -Eic "${RE_MOT}" "${OUTPUT_TXT}")"

			# On génère le dump de contexte (2 lignes)
			grep -EiC 2 "${RE_MOT}" "${OUTPUT_TXT}" > "${OUTPUT_CTX}"

			# Lien vers le fichier contexte
			context_cell="<a href=\"../${OUTPUT_CTX_REL}\">${OUTPUT_CTX_REL}</a>"

			# Création du concordancier
			concordance_cell="<a href="../${OUTPUT_CON_REL}">${OUTPUT_CON_REL}</a>"
			# Header
			cat "${BASE_DIR}/templates/concordancier.head.tpl" > "${OUTPUT_CON}"
			${SED_BIN} -re "s/%LANG%/${TABLE_LANG}/" -i "${OUTPUT_CON}"
			# Body (à partir du template)
			CONC_RE_PATTERN="(.{0,50})${RE_MOT}(.{0,50})"
			grep -Eio "${CONC_RE_PATTERN}" "${OUTPUT_TXT}" | \
				${SED_BIN} -re "s#${CONC_RE_PATTERN}#${CONC_ROW_TEMPLATE}#gi" >> "${OUTPUT_CON}"
			# Footer
			cat "${BASE_DIR}/templates/table.foot.tpl" >> "${OUTPUT_CON}"
			cat "${BASE_DIR}/templates/footer.tpl" >> "${OUTPUT_CON}"
		else
			# Pas de contexte si pas de match ;).
			context_cell="<span class=\"has-text-danger\">N/A</span>"
			concordance_cell="<span class=\"has-text-danger\">N/A</span>"
		fi
	else
		# On veut faire ressortir les erreurs
		status_color="danger"
		>&2 echo "* Impossible d'accèder à la page ${line}"
		# Mais on a quand même une ligne à générer pour cette page, donc on continue l'itération jusqu'au bout
	fi

	# Besoin de l'option -e pour qu'echo gère les caractères de controle en version échappée
	# IDX | URL | STATUS | CHARSET | WC
	# En TSV:
	#echo -e "${line_nb}\t${line}\t${http_status}\t${page_encoding}\t${word_count}"

	# Si le lien est malformé, on corrige la chose pour notre href...
	if [[ ! ${line} =~ ^https?:// ]] ; then
		# Et on espère que ça passe en HTTPS :D
		url="https://${line}"
	else
		url="${line}"
	fi

	cat << EoS
							<tr>
								<td>${line_nb}</td>
								<td><a href="${url}">${line}</a></td>
								<td><span class="has-text-${status_color}">${http_status}</span></td>
								<td>${page_encoding}</td>
								<td>${word_count}</td>
								<td><a href="../${OUTPUT_HTML_REL}">${OUTPUT_HTML_REL}</a></td>
								<td><a href="../${OUTPUT_TXT_REL}">${OUTPUT_TXT_REL}</a></td>
								<td>${match_count}</td>
								<td>${context_cell}</td>
								<td>${concordance_cell}</td>
							</tr>
EoS

	# Et du coup on incrémente notre compteur à la main
	((line_nb++))
done < "${INPUT_URL_LIST}"

## Fin du HTML
cat "${BASE_DIR}/templates/table.foot.tpl"
cat "${BASE_DIR}/templates/footer.tpl"
