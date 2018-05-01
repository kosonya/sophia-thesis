all:
	pdflatex proposal.tex
	bibtex proposal.aux
	pdflatex proposal.tex
	pdflatex proposal.tex

clean:
	rm proposal.aux proposal.bbl proposal.blg proposal.log proposal.pdf proposal.toc

include Makefile.piotrm