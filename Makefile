.PHONY: build

all    :  build;
build  :; ./build.sh
clean  :; dapp clean
test   :; ./test.sh $(MATCH)
deploy :; dapp create GUniLPOracle
