SHELL := /bin/bash

.DEFAULT_GOAL := help

# Python 解释器路径
PYTHON ?= ./.venv/bin/python
# benchmark CLI 入口
CLI := PYTHONPATH=. $(PYTHON) -m autobench.cli

# 全局默认模型名；各阶段未显式指定时回退到这里
MODEL := qwen3.6-plus
# 全局默认 OpenAI-compatible base URL；各阶段未显式指定时回退到这里
BASE_URL := https://dashscope.aliyuncs.com/compatible-mode/v1
# 全局默认 API key 环境变量名；各阶段未显式指定时回退到这里
API_KEY_ENV := DASHSCOPE_API_KEY

# 运行配置文件
CONFIG ?= configs/baseline.json
# case 目录
CASES_DIR ?= cases-v1
# 输出根目录
OUTPUT_ROOT ?= outputs
# 指定 run id；为空则自动生成
RUN_ID ?=
# 只运行/检查指定 case，支持空格或逗号分隔
CASE_IDS ?=
# benchmark case 级并发数
CONCURRENCY ?= 1
# 可选的 unittest 模块/用例选择器
TEST ?=

# debug-only：真值时保留最后一个 supported case 的 runtime 目录；要求 CONCURRENCY=1
KEEP_RUNTIME ?=
# 真值时禁用 success_mode=judge 的主成功判定
DISABLE_PRIMARY_SUCCESS_JUDGE ?=
# 真值时减少 CLI 输出
QUIET ?=

# benchmark 主执行模型的 OpenAI-compatible base URL；为空时回退到 BASE_URL
PROVIDER_BASE_URL ?=
# benchmark 主执行模型名；为空时回退到 MODEL
PROVIDER_MODEL ?=
# benchmark 主执行模型 API key 对应的环境变量名；为空时回退到 API_KEY_ENV
PROVIDER_API_KEY_ENV ?=
# OpenClaw gateway Docker 镜像
GATEWAY_IMAGE ?=
# OpenClaw gateway token 对应的环境变量名
GATEWAY_TOKEN_ENV ?=
# 单次请求超时时间（秒）
REQUEST_TIMEOUT_SEC ?=

# 评估 judge 模型的 OpenAI-compatible base URL；为空时回退到 BASE_URL
JUDGE_BASE_URL ?=
# 评估 judge 模型名；为空时回退到 MODEL
JUDGE_MODEL ?=
# 评估 judge 模型 API key 对应的环境变量名；为空时回退到 API_KEY_ENV
JUDGE_API_KEY_ENV ?=

empty :=
space := $(empty) $(empty)
comma := ,

truthy = $(filter 1 true TRUE yes YES y Y on ON,$(strip $(1)))

CASE_ID_WORDS = $(strip $(subst $(comma),$(space),$(CASE_IDS)))
CASE_ID_ARGS = $(foreach id,$(CASE_ID_WORDS),--case-id $(id))

EFFECTIVE_PROVIDER_MODEL = $(strip $(or $(PROVIDER_MODEL),$(MODEL)))
EFFECTIVE_PROVIDER_BASE_URL = $(strip $(or $(PROVIDER_BASE_URL),$(BASE_URL)))
EFFECTIVE_PROVIDER_API_KEY_ENV = $(strip $(or $(PROVIDER_API_KEY_ENV),$(API_KEY_ENV)))
EFFECTIVE_JUDGE_MODEL = $(strip $(or $(JUDGE_MODEL),$(MODEL)))
EFFECTIVE_JUDGE_BASE_URL = $(strip $(or $(JUDGE_BASE_URL),$(BASE_URL)))
EFFECTIVE_JUDGE_API_KEY_ENV = $(strip $(or $(JUDGE_API_KEY_ENV),$(API_KEY_ENV)))

.PHONY: help test dry check run report clean-run stop-docker

help: ## Show available targets and key variables
	@awk 'BEGIN {FS = ":.*## "; printf "\nTargets:\n"} /^[a-zA-Z0-9_.-]+:.*## / {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@printf "\nCommon variables:\n"
	@printf "  MODEL=%s\n" "$(MODEL)"
	@printf "  BASE_URL=%s\n" "$(BASE_URL)"
	@printf "  API_KEY_ENV=%s\n" "$(API_KEY_ENV)"
	@printf "  CONFIG=%s\n" "$(CONFIG)"
	@printf "  CASES_DIR=%s\n" "$(CASES_DIR)"
	@printf "  OUTPUT_ROOT=%s\n" "$(OUTPUT_ROOT)"
	@printf "  CASE_IDS=<space-or-comma-separated ids>\n"
	@printf "  RUN_ID=<existing or new run id>\n"
	@printf "\nExamples:\n"
	@printf "  make test\n"
	@printf "  make dry CASE_IDS=41\n"
	@printf "  make run CASE_IDS='29 30 70' BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1 API_KEY_ENV=DASHSCOPE_API_KEY PROVIDER_MODEL=dashscope/qwen3.6-plus JUDGE_MODEL=qwen3.6-plus\n"
	@printf "  make report RUN_ID=run-web-public-20260425-1\n\n"
	@printf "  make stop-docker\n\n"

test: ## Run unit tests; optional TEST=tests.test_cli_dry_run
	@if [ -n "$(TEST)" ]; then \
		PYTHONPATH=. $(PYTHON) -m unittest $(TEST); \
	else \
		PYTHONPATH=. $(PYTHON) -m unittest discover -s tests; \
	fi

dry: ## Load and validate cases only, without execution or report artifacts
	@$(CLI) \
		--config "$(CONFIG)" \
		--cases-dir "$(CASES_DIR)" \
		--output-root "$(OUTPUT_ROOT)" \
		$(if $(RUN_ID),--run-id "$(RUN_ID)") \
		$(CASE_ID_ARGS) \
		--concurrency "$(CONCURRENCY)" \
		$(if $(call truthy,$(QUIET)),--quiet) \
		--dry

check: dry ## Alias of dry

run: ## Execute benchmark cases end-to-end
	@$(CLI) \
		--config "$(CONFIG)" \
		--cases-dir "$(CASES_DIR)" \
		--output-root "$(OUTPUT_ROOT)" \
		$(if $(RUN_ID),--run-id "$(RUN_ID)") \
		$(CASE_ID_ARGS) \
		--concurrency "$(CONCURRENCY)" \
		$(if $(call truthy,$(KEEP_RUNTIME)),--keep-runtime) \
		$(if $(EFFECTIVE_PROVIDER_BASE_URL),--provider-base-url "$(EFFECTIVE_PROVIDER_BASE_URL)") \
		$(if $(EFFECTIVE_PROVIDER_MODEL),--provider-model "$(EFFECTIVE_PROVIDER_MODEL)") \
		$(if $(EFFECTIVE_PROVIDER_API_KEY_ENV),--provider-api-key-env "$(EFFECTIVE_PROVIDER_API_KEY_ENV)") \
		$(if $(GATEWAY_IMAGE),--gateway-image "$(GATEWAY_IMAGE)") \
		$(if $(GATEWAY_TOKEN_ENV),--gateway-token-env "$(GATEWAY_TOKEN_ENV)") \
		$(if $(REQUEST_TIMEOUT_SEC),--request-timeout-sec "$(REQUEST_TIMEOUT_SEC)") \
		$(if $(call truthy,$(DISABLE_PRIMARY_SUCCESS_JUDGE)),--disable-primary-success-judge) \
		$(if $(EFFECTIVE_JUDGE_BASE_URL),--judge-base-url "$(EFFECTIVE_JUDGE_BASE_URL)") \
		$(if $(EFFECTIVE_JUDGE_MODEL),--judge-model "$(EFFECTIVE_JUDGE_MODEL)") \
		$(if $(EFFECTIVE_JUDGE_API_KEY_ENV),--judge-api-key-env "$(EFFECTIVE_JUDGE_API_KEY_ENV)") \
		$(if $(call truthy,$(QUIET)),--quiet)

report: ## Rebuild summary.json and report.md from an existing run
	@test -n "$(RUN_ID)" || { echo "RUN_ID is required, e.g. make report RUN_ID=run-20260425-000001"; exit 1; }
	@$(CLI) \
		--report-only \
		--run-id "$(RUN_ID)" \
		--output-root "$(OUTPUT_ROOT)" \
		$(if $(call truthy,$(QUIET)),--quiet)

clean-run: ## Remove one run directory; requires RUN_ID
	@test -n "$(RUN_ID)" || { echo "RUN_ID is required, e.g. make clean-run RUN_ID=run-20260425-000001"; exit 1; }
	@rm -rf "$(OUTPUT_ROOT)/runs/$(RUN_ID)"

stop-docker: ## Stop/remove benchmark-created containers and legacy networks
	@containers="$$(docker ps -aq --filter 'name=autobench-gateway-')"; \
	if [ -n "$$containers" ]; then \
		echo "Removing benchmark containers: $$containers"; \
		docker rm -f $$containers; \
	else \
		echo "No benchmark containers found."; \
	fi
	@networks="$$(docker network ls -q --filter 'name=autobench-')"; \
	if [ -n "$$networks" ]; then \
		echo "Removing legacy benchmark networks: $$networks"; \
		docker network rm $$networks; \
	else \
		echo "No legacy benchmark networks found."; \
	fi
