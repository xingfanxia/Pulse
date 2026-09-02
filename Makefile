# clauth integration (fork-only). `make test` is what the autonomous-grind
# verify-before-clear hook recognises; it runs the frozen verify script.
CLP_HOOK_BUDGET ?= 52

.PHONY: test verify
test verify:
	CLP_HOOK_BUDGET=$(CLP_HOOK_BUDGET) Scripts/clauth-verify.sh
