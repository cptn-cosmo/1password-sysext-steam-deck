.PHONY: all setup docs clean

all: setup

setup:
	./scripts/10_setup.sh

docs:
	./scripts/50_docs.sh

hooks: .git/hooks/pre-commit
	ln -s -f ../../hooks/pre-commit .git/hooks/pre-commit

clean:
	./scripts/00_clean.sh
