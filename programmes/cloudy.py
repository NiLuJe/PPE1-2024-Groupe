#!/usr/bin/env python3

import csv
from pathlib import Path
from wordcloud import WordCloud, STOPWORDS
import nltk
from nltk.corpus import stopwords
import sys

# Correspondance ISO <-> English pour NLTK...
LANG_NAMES = {
	"FR": "French",
	"EN": "English",
	"RU": "Russian"
}

def main(pals_ctx: str | Path, image: str | Path):
	"""Front-end à WordCloud qui utilise nos résultats PALS"""

	# On veut des objets kisontbien pour gérer les chemins...
	pals_ctx = Path(pals_ctx)
	image = Path(image)

	# On récupère la langue depuis le nom du fichier...
	lang = pals_ctx.stem.split("-")
	lang_name = LANG_NAMES[lang[-1]]

	# On parse nos résultats PALS pour construire un dict[str, float] (coocccurent: specifité)
	freqs = {}
	# C'est du TSV, ça nous facilite la tâche...
	with open(pals_ctx, newline="") as f:
		# On détecte le dialecte
		dialect = csv.Sniffer().sniff(f.read(1024))
		f.seek(0)

		# Et on replit notre dico ligne à ligne
		reader = csv.DictReader(f, dialect=dialect)
		for row in reader:
			freqs[row["token"]] = float(row["specificity"])

	# Et on choppe la liste de stopwords qui va bien pour la langue
	# On ajoute ça à celle de WordCloud (bon, c'est que de l'anglais, mais ça peut pas faire de mal)
	stop_words = set(STOPWORDS).union(set(stopwords.words(lang_name)))
	# NOTE: Éventuellement, on peut rajouter d'autres stopwords en dur, si besoin...

	# On instancie WC
	wc = WordCloud(background_color="black", width=800, height=400, scale=2, max_words=200, stopwords=stop_words)

	# On génère le bouzin, en fonction de nos résultats de PALS plutôt que de l'algo interne
	wc.generate_from_frequencies(freqs)

	# Et on enregistre l'image
	wc.to_file(image)

	# Pour le fun, on en génère un second avec l'algo de base ;).
	wc = WordCloud(background_color="black", width=800, height=400, scale=2, max_words=200, stopwords=stop_words)
	wc.generate(pals_ctx.with_name(pals_ctx.name.replace("processed-", "")).read_text())
	wc.to_file(image.with_name("std-" + image.name))


# Main entry-point
if __name__ == "__main__":
	# On a besoin du corpus stopwords de NLTK...
	nltk.download("stopwords")

	# Et on forward les arguments
	main(*sys.argv[1:])
