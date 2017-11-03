ifndef K_VERSION
$(error K_VERSION not set. Please use the Build script, instead of running make directly)
endif

# Common to all versions of K
# ===========================

.PHONY: all clean build tangle defn proofs presentation split-tests test

all: build split-tests

clean:
	rm -r .build
	find tests/proofs/ -name '*.k' -delete

build: tangle .build/${K_VERSION}/ethereum-kompiled/extras/timestamp

# Tangle from *.md files
# ----------------------

tangle: defn proofs presentation

defn_dir=.build/${K_VERSION}
defn_files=${defn_dir}/ethereum.k ${defn_dir}/data.k ${defn_dir}/evm.k ${defn_dir}/analysis.k ${defn_dir}/krypto.k ${defn_dir}/verification.k
defn: $(defn_files)

.build/${K_VERSION}/%.k: %.md
	@echo "==  tangle: $@"
	mkdir -p $(dir $@)
	pandoc-tangle --from markdown --to code-k --code ${K_VERSION} $< > $@

proof_dir=tests/proofs
proof_files=${proof_dir}/sum-to-n-spec.k \
			${proof_dir}/hkg/allowance-spec.k \
			${proof_dir}/hkg/approve-spec.k \
			${proof_dir}/hkg/balanceOf-spec.k \
			${proof_dir}/hkg/transfer-else-spec.k ${proof_dir}/hkg/transfer-then-spec.k \
			${proof_dir}/hkg/transferFrom-else-spec.k ${proof_dir}/hkg/transferFrom-then-spec.k \
			${proof_dir}/bad/hkg-token-buggy-spec.k

proofs: $(proof_files)

tests/proofs/sum-to-n-spec.k: proofs/sum-to-n.md
	@echo "==  tangle: $@"
	mkdir -p $(dir $@)
	pandoc-tangle --from markdown --to code-k --code sum-to-n $< > $@

tests/proofs/hkg/%-spec.k: proofs/hkg.md
	@echo "==  tangle: $@"
	mkdir -p $(dir $@)
	pandoc-tangle --from markdown --to code-k --code $* $< > $@

tests/proofs/bad/hkg-token-buggy-spec.k: proofs/token-buggy-spec.md
	@echo "==  tangle: $@"
	mkdir -p $(dir $@)
	pandoc-tangle --from markdown --to code-k --code k $< > $@

presentation: .build/presentation/presentation.pdf

.build/presentation/presentation.pdf: .build/presentation/presentation.md .build/presentation/presentation.markdown
	@echo "== pandoc: $@"
	mkdir -p $(dir $@)
	cd .build/presentation \
		&& pandoc --from markdown --to markdown --template presentation presentation.md \
		 | pandoc --from markdown --to beamer --output presentation.pdf

presentation_files=data.md evm.md proofs/sum-to-n.md Makefile
presentation_sects='Modulo Arithmetic|Word Arithmetic|As a cons-list|WordStack Append|Single Step|Expressions|Local Memory|Account Storage Operations|Call Operations|SSTORE Gas|Csstore|Others|Schedule Constants|Default Schedule|EIP150 Schedule|Sum To N Program and Claim|Main Claim|Circularity (Loop Invariant)'

.build/presentation/presentation.md: $(presentation_files)
	@echo "==  tangle: $@"
	mkdir -p $(dir $@)
	pandoc-tangle --from markdown --to markdown \
		--section $(presentation_sects) \
		$(presentation_files) > $@

# Tests
# -----

split-tests: vm-tests blockchain-tests

vm-tests: tests/VMTests/vmArithmeticTest/make.timestamp \
		  tests/VMTests/vmBitwiseLogicOperationTest/make.timestamp \
		  tests/VMTests/vmBlockInfoTest/make.timestamp \
		  tests/VMTests/vmEnvironmentalInfoTest/make.timestamp \
		  tests/VMTests/vmIOandFlowOperationsTest/make.timestamp \
		  tests/VMTests/vmLogTest/make.timestamp \
		  tests/VMTests/vmPerformanceTest/make.timestamp \
		  tests/VMTests/vmPushDupSwapTest/make.timestamp \
		  tests/VMTests/vmSha3Test/make.timestamp \
		  tests/VMTests/vmSystemOperationsTest/make.timestamp \
		  tests/VMTests/vmtests/make.timestamp \
		  tests/VMTests/vmInputLimits/make.timestamp \
		  tests/VMTests/vmInputLimitsLight/make.timestamp

blockchain-tests: \
				  $(patsubst tests/ethereum-tests/%.json,tests/%/make.timestamp, $(wildcard tests/ethereum-tests/BlockchainTests/GeneralStateTests/*/*.json)) \

#passing_test_file=tests/passing.expected
#blockchain_tests=$(shell cat ${passing_test_file})
blockchain_tests=$(wildcard tests/BlockchainTests/*/*/*/*.json)
all_tests=$(wildcard tests/VMTests/*/*.json) ${blockchain_tests}
skipped_tests=$(wildcard tests/VMTests/vmPerformanceTest/*.json) \
   $(wildcard tests/BlockchainTests/GeneralStateTests/*/*/*_Byzantium.json) \
   $(wildcard tests/BlockchainTests/GeneralStateTests/*/*/*_Constantinople.json) \
   $(wildcard tests/BlockchainTests/GeneralStateTests/stQuadraticComplexityTest/*/*.json)

passing_tests=$(filter-out ${skipped_tests}, ${all_tests})
passing_blockchain_tests=$(filter-out ${skipped_tests}, ${blockchain_tests})
passing_targets=${passing_tests:=.test}
passing_blockchain_targets=${passing_blockchain_tests:=.test}

test: $(passing_targets)
blockchain-test: $(passing_blockchain_targets)

tests/VMTests/%.test: tests/VMTests/% build
	./vmtest $<
tests/BlockchainTests/%.test: tests/BlockchainTests/% build
	./blockchaintest $<

tests/%/make.timestamp: tests/ethereum-tests/%.json
	@echo "==   split: $@"
	mkdir -p $(dir $@)
	tests/split-test.py $< $(dir $@)
	touch $@

tests/ethereum-tests/%.json:
	@echo "==  git submodule: cloning upstreams test repository"
	git submodule update --init

# UIUC K Specific
# ---------------

.build/uiuck/ethereum-kompiled/extras/timestamp: $(defn_files)
	@echo "== kompile: $@"
	kompile --debug --main-module ETHEREUM-SIMULATION \
					--syntax-module ETHEREUM-SIMULATION $< --directory .build/uiuck

# RVK Specific
# ------------

.build/rvk/ethereum-kompiled/extras/timestamp: .build/rvk/ethereum-kompiled/interpreter
.build/rvk/ethereum-kompiled/interpreter: $(defn_files) KRYPTO.ml
	@echo "== kompile: $@"
	kompile --debug --main-module ETHEREUM-SIMULATION \
					--syntax-module ETHEREUM-SIMULATION $< --directory .build/rvk \
					--hook-namespaces KRYPTO --gen-ml-only -O3 --non-strict
	ocamlfind opt -c .build/rvk/ethereum-kompiled/constants.ml -package gmp -package zarith
	ocamlfind opt -c -I .build/rvk/ethereum-kompiled KRYPTO.ml -package cryptokit -package secp256k1
	ocamlfind opt -a -o semantics.cmxa KRYPTO.cmx
	ocamlfind remove ethereum-semantics-plugin
	ocamlfind install ethereum-semantics-plugin META semantics.cmxa semantics.a KRYPTO.cmi KRYPTO.cmx
	kompile --debug --main-module ETHEREUM-SIMULATION \
					--syntax-module ETHEREUM-SIMULATION $< --directory .build/rvk \
					--hook-namespaces KRYPTO --packages ethereum-semantics-plugin -O3 --non-strict
	cd .build/rvk/ethereum-kompiled && ocamlfind opt -o interpreter constants.cmx prelude.cmx plugin.cmx parser.cmx lexer.cmx run.cmx interpreter.ml -package gmp -package dynlink -package zarith -package str -package uuidm -package unix -linkpkg -inline 20 -nodynlink -O3
