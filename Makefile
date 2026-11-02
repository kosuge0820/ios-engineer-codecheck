# iOSEngineerCodeCheck の入り口コマンド。ローカルと CI（.github/workflows/ci.yml）は同じターゲットを使う。
#
#   make            ターゲット一覧を表示
#   make test       単体テスト（結果は build/test.xcresult、要約を標準出力に出す）
#
# 変数は環境変数または引数で上書きできる: make test SIMULATOR_NAME="iPhone 17 Pro" SIMULATOR_OS=27.0

SHELL := /bin/bash
.DEFAULT_GOAL := help
# Xcode の Command Line Tools に入る GNU make 3.81 は .SHELLFLAGS を無視するので、
# パイプを使うレシピでは tee に終了コードを隠されないよう各レシピ内で set -o pipefail する
PIPEFAIL = set -o pipefail;

PROJECT        ?= iOSEngineerCodeCheck.xcodeproj
SCHEME         ?= iOSEngineerCodeCheck
TEST_PLAN      ?= iOSEngineerCodeCheck
UI_TEST_PLAN   ?= iOSEngineerCodeCheckUI
SIMULATOR_NAME ?= iPhone 17
SIMULATOR_OS   ?= latest
DESTINATION    ?= platform=iOS Simulator,name=$(SIMULATOR_NAME),OS=$(SIMULATOR_OS)
BUILD_DIR      ?= build
DERIVED_DATA   ?= $(BUILD_DIR)/DerivedData
RESULT_BUNDLE  ?= $(BUILD_DIR)/test.xcresult
REPEAT_RESULT_BUNDLE ?= $(BUILD_DIR)/test-repeat.xcresult
REPEAT_TESTS   ?= iOSEngineerCodeCheckTests/SearchModelTests
REPEAT_COUNT   ?= 20
LOG_SUBSYSTEM  ?= jp.yumemi.iOSEngineerCodeCheck
# 署名は不要。Swift 警告のエラー扱いはプロジェクト設定（SWIFT_TREAT_WARNINGS_AS_ERRORS）で有効にしてあり、Xcode と同じ結果になる
XCODEBUILD_FLAGS ?= CODE_SIGNING_ALLOWED=NO

XCODEBUILD = xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA)
SOURCE_DIRS = iOSEngineerCodeCheck iOSEngineerCodeCheckTests iOSEngineerCodeCheckUITests

.PHONY: help build test test-repeat ui-test lint format report log clean check-tools

help: ## ターゲット一覧
	@echo "使い方: make <target> [VAR=value]"
	@echo
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{ printf "  %-12s %s\n", $$1, $$2 }'
	@echo
	@echo "主な変数（現在値）:"
	@echo "  SIMULATOR_NAME=$(SIMULATOR_NAME)  SIMULATOR_OS=$(SIMULATOR_OS)"
	@echo "  DESTINATION=$(DESTINATION)"
	@echo "  BUILD_DIR=$(BUILD_DIR)  RESULT_BUNDLE=$(RESULT_BUNDLE)"

check-tools:
	@command -v xcodebuild >/dev/null || { echo "xcodebuild が見つかりません。Xcode をインストールし xcode-select で選択してください" >&2; exit 1; }
	@mkdir -p $(BUILD_DIR)

build: check-tools ## アプリと単体・UI テストターゲットをビルド（Swift 警告はプロジェクト設定でエラー扱い）。ログ: build/build.log
	$(PIPEFAIL) $(XCODEBUILD) build-for-testing -testPlan $(TEST_PLAN) -testPlan $(UI_TEST_PLAN) $(XCODEBUILD_FLAGS) 2>&1 | tee $(BUILD_DIR)/build.log

# xcodebuild test を実行し、終了コードを保ったまま要約を出す共通レシピ
# 引数: 1 = xcresult の出力先, 2 = ログファイル名, 3 = xcodebuild test への追加引数
define run-tests
	$(PIPEFAIL) status=0; summary_status=0; \
	rm -rf $(1); \
	$(XCODEBUILD) test $(3) -resultBundlePath $(1) $(XCODEBUILD_FLAGS) 2>&1 | tee $(BUILD_DIR)/$(2) || status=$$?; \
	./scripts/summarize-xcresult.sh $(1) || summary_status=$$?; \
	[ $$status -ne 0 ] || status=$$summary_status; \
	exit $$status
endef

test: check-tools ## 単体テスト（テストプラン iOSEngineerCodeCheck）。結果: build/test.xcresult、ログ: build/test.log
	$(call run-tests,$(RESULT_BUNDLE),test.log,-testPlan $(TEST_PLAN))

test-repeat: check-tools ## 非同期競合の flaky 検出: SearchModelTests を REPEAT_COUNT 回（既定 20）繰り返す。計測の影響を避けるためカバレッジは無効
	$(call run-tests,$(REPEAT_RESULT_BUNDLE),test-repeat.log,-testPlan $(TEST_PLAN) -only-testing:$(REPEAT_TESTS) -test-iterations $(REPEAT_COUNT) -run-tests-until-failure -enableCodeCoverage NO)

ui-test: check-tools ## UI テスト（テストプラン iOSEngineerCodeCheckUI。make test では走らない。テストが 0 件なら失敗）
	$(call run-tests,$(BUILD_DIR)/ui-test.xcresult,ui-test.log,-testPlan $(UI_TEST_PLAN))

lint: ## 静的解析（Xcode 同梱の swift-format、設定は .swift-format）
	xcrun swift-format lint --strict --recursive $(SOURCE_DIRS)

format: ## swift-format で整形（ローカル用。CI では実行しない）
	xcrun swift-format format --in-place --recursive $(SOURCE_DIRS)

report: ## 直近の build/test.xcresult の要約を表示
	./scripts/summarize-xcresult.sh $(RESULT_BUNDLE)

log: ## 起動中シミュレータのアプリログ（os.Logger、subsystem=jp.yumemi.iOSEngineerCodeCheck）を流す
	xcrun simctl spawn booted log stream --level debug --style compact --predicate 'subsystem == "$(LOG_SUBSYSTEM)"'

clean: ## build/ を削除
	rm -rf $(BUILD_DIR)
