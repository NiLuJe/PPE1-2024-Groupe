#!/usr/bin/env bash

# Fail early, fail often.
set -euo pipefail
# Debugging
#set -x

# On préfère certains outils GNU sous macOS...
if [ "$(uname -s)" == "Darwin" ] ; then
	UCONV_BIN="/opt/homebrew/opt/icu4c/bin/uconv"
	HEAD_BIN="ghead"
	WC_BIN="gwc"
else
	UCONV_BIN="uconv"
	HEAD_BIN="head"
	WC_BIN="wc"
fi

# Validation basique du paramètre
if [ $# -ne 1 ] ; then
	echo "usage: ${0} <liste_url>"
	exit 1
fi

INPUT_URL_LIST="${1}"
if [ -z "${INPUT_URL_LIST}" ] ; then
	echo "La liste d'URLs ne peut pas être une chaîne vide."
	exit 1
fi

# On va aussi vérifier qu'on puisse accéder au fichier, tant qu'à faire
if ! [ -f "${INPUT_URL_LIST}" ] ; then
	echo "Impossible d'accéder au fichier '${INPUT_URL_LIST}' (problème de chemin?)"
	exit 1
fi
if ! [ -r "${INPUT_URL_LIST}" ] ; then
	echo "Impossible de lire le fichier '${INPUT_URL_LIST}' (problème de permissions?)"
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
	"Alèd Eliza!"
)
MOT=""

# On va chopper le mot dans la langue de la liste d'URL automagiquement
for i in "${!LANG_ARRAY[@]}" ; do
	lang="${LANG_ARRAY[${i}]}"

	if [ "${lang}" = "${TABLE_LANG}" ] ; then
		MOT="${WORD_ARRAY[${i}]}"
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
cat << EoS
<!DOCTYPE html>
<html lang="fr">
	<head>
		<meta charset="UTF-8">
		<meta name="viewport" content="width=device-width, initial-scale=1">
		<title>Projet PPE1 2024-2025 - Tableau ${TABLE_LANG}</title>
		<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bulma@1.0.2/css/bulma.min.css">
		<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.7.1/css/all.min.css"/>
	</head>
	<body>
		<nav class="navbar is-fixed-top has-shadow" role="navigation" aria-label="main navigation">
			<div id="navbar-ppe" class="navbar-menu">
				<div class="navbar-start">
					<a class="navbar-item" href="../index.html"> Accueil </a>
					<a class="navbar-item is-active" href=""> Tableaux </a>
				</div>
			</div>
		</nav>

		<section class="section">
			<div class="container">
				<div class="hero has-text-centered">
					<div class="hero-body">
						<h1 class="title">Projet PPE1 2024-2025</h1>
					</div>
				</div>
				<nav class="tabs is-centered">
					<ul>
						<li><a href="tableau-fr.html">FR</a></li>
						<li><a href="tableau-en.html">EN</a></li>
						<li><a href="tableau-ru.html">RU</a></li>
					</ul>
				</nav>
				<div class="box">
					<table class="table is-bordered is-striped is-hoverable mx-auto">
						<thead>
							<tr>
								<th>Ligne</th>
								<th>URL</th>
								<th>Code HTTP</th>
								<th>Encodage</th>
								<th>Nombre de mots</th>
								<th>HTML</th>
								<th>Texte Brut</th>
								<th>Compte</th>
								<th>Contexte</th>
							</tr>
						</thead>
						<tbody>
EoS

# On va avoir besoin de tenir un compte des lignes parcourues
line_nb=1
while read -r line ; do
	# Si la ligne commence par un #, on passe
	if echo "${line}" | grep -Eq "^#" ; then
		continue
	fi

	# On teste une requête GET via cURL (en suivant les redirections),
	# et on lui demande de nous écrire le code HTTP et la valeur de l'en-tête Content-Type en toute fin de sortie, sur une ligne dédiée.
	OUTPUT_HTML="aspirations/${TABLE_LANG}-${line_nb}.html"
	OUTPUT_TXT="dumps-text/${TABLE_LANG}-${line_nb}.txt"
	OUTPUT_CTX="contextes/${TABLE_LANG}-${line_nb}.txt"

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
			page_encoding="$(head -n 1 "${OUTPUT_HTML}" | sed -re "s/.*encoding\s*=\s*[\'\"]?([-_:[:alnum:]]+)[\'\"]?.*/\1/")"
		else
			# On va garder le premier (vu que la balise devrait être dans le bloc head)
			# charset= qu'on croise dans le code et croiser les doigts ;p.
			# c.f., https://www.w3.org/International/questions/qa-html-encoding-declarations.var
			#     & https://www.w3schools.com/html/html_charset.asp
			page_encoding="$(grep charset "${OUTPUT_HTML}" | head -n 1 | sed -re "s/.*charset\s*=\s*[\'\"]?([-_:[:alnum:]]+)[\'\"]?.*/\1/")"
		fi

		# On va laisser à lynx le job d'interpréter le HTML pour qu'il ne nous reste que le texte
		lynx -display_charset=UTF-8 -dump -nolist "${OUTPUT_HTML}" > "${OUTPUT_TXT}"
		# GNU wc pour éviter l'indentation de BSD wc...
		word_count="$(${WC_BIN} -w "${OUTPUT_TXT}" | cut -f1 -d" ")"

		# Grep retourne un code d'erreur si le mot n'est pas identifié!
		if grep -q "${MOT}" "${OUTPUT_TXT}" ; then
			# On compte le nombre d'occurrences
			match_count="$(grep -c "${MOT}" "${OUTPUT_TXT}")"

			# On génère le dump de contexte (2 lignes)
			grep -C 2 "${MOT}" "${OUTPUT_TXT}" > "${OUTPUT_CTX}"
		fi
	else
		# On veut faire ressortir les erreurs
		status_color="danger"
		>&2 echo "* Impossible d'accèder à la page ${line}"
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
								<td><a href="../${OUTPUT_HTML}">${OUTPUT_HTML}</a></td>
								<td><a href="../${OUTPUT_TXT}">${OUTPUT_TXT}</a></td>
								<td>${match_count}</td>
								<td><a href="../${OUTPUT_CTX}">${OUTPUT_CTX}</a></td>
							</tr>
EoS

	# Et du coup on incrémente notre compteur à la main
	((line_nb++))
done < "${INPUT_URL_LIST}"

## Fin du HTML
cat << EoS
						</tbody>
					</table>
				</div>
			</div>
		</section>

		<footer class="footer">
			<div class="content has-text-centered">
				<span class="icon-text">
					<span class="icon">
						<i class="fas fa-brands fa-github"></i>
					</span>
					<span>
						<a href="https://github.com/NiLuJe/PPE1-2024">NiLuJe</a>
					</span>
				</span>
			</div>
		</footer>
	</body>
</html>
EoS
