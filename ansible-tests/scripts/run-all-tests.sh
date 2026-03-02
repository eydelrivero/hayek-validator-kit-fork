#!/bin/bash
# Run All Scenarios - Test Suite Runner
# Usage: run-all-tests.sh [--continue-on-error]
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CONTINUE_ON_ERROR=false
if [[ "${1:-}" == "--continue-on-error" ]]; then
    CONTINUE_ON_ERROR=true
    set +e  # Don't exit on error
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}🧪 HAYEK VALIDATOR KIT - ALL TESTS${NC}"
echo -e "${BLUE}========================================${NC}"

# Get all available scenarios
SCENARIOS=()
PROJECT_DIR="/hayek-validator-kit"
MOLECULE_DIR="$PROJECT_DIR/ansible-tests/molecule"

if [ -d "$MOLECULE_DIR" ]; then
    for scenario_dir in "$MOLECULE_DIR"/*; do
        if [ -d "$scenario_dir" ]; then
            scenario_name=$(basename "$scenario_dir")
            SCENARIOS+=("$scenario_name")
        fi
    done
fi

if [ ${#SCENARIOS[@]} -eq 0 ]; then
    echo -e "${RED}❌ No scenarios found in $MOLECULE_DIR${NC}"
    exit 1
fi

echo -e "${YELLOW}📋 Found ${#SCENARIOS[@]} scenarios:${NC}"
for scenario in "${SCENARIOS[@]}"; do
    echo -e "   • $scenario"
done
echo ""

# Results tracking
PASSED_SCENARIOS=()
FAILED_SCENARIOS=()
START_TIME=$(date +%s)

# Function to get scenario parameters
get_scenario_params() {
    local scenario_name="$1"
    
    case "$scenario_name" in
        "iam_manager_tests")
            echo "-- -e csv_file=iam_setup.csv"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Function to run a single scenario
run_scenario() {
    local scenario="$1"
    local params
    params=$(get_scenario_params "$scenario")
    
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}🎯 Running scenario: $scenario${NC}"
    echo -e "${BLUE}========================================${NC}"
    
    local cmd="molecule test -s $scenario"
    if [ -n "$params" ]; then
        cmd="$cmd $params"
    fi
    
    echo -e "${YELLOW}▶️  Executing: $cmd${NC}"
    
    local scenario_start=$(date +%s)
    
    if eval "$cmd"; then
        local scenario_end=$(date +%s)
        local scenario_duration=$((scenario_end - scenario_start))
        echo -e "${GREEN}✅ $scenario: PASSED (${scenario_duration}s)${NC}"
        PASSED_SCENARIOS+=("$scenario")
        return 0
    else
        local scenario_end=$(date +%s)
        local scenario_duration=$((scenario_end - scenario_start))
        echo -e "${RED}❌ $scenario: FAILED (${scenario_duration}s)${NC}"
        FAILED_SCENARIOS+=("$scenario")
        
        if [ "$CONTINUE_ON_ERROR" = false ]; then
            echo -e "${RED}💥 Stopping execution due to failure${NC}"
            exit 1
        fi
        return 1
    fi
}

# Run all scenarios
for scenario in "${SCENARIOS[@]}"; do
    run_scenario "$scenario"
    echo ""
done

# Final report
END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}📊 FINAL RESULTS${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}⏱️  Total duration: ${TOTAL_DURATION}s${NC}"
echo -e "${YELLOW}📈 Total scenarios: ${#SCENARIOS[@]}${NC}"
echo -e "${GREEN}✅ Passed: ${#PASSED_SCENARIOS[@]}${NC}"
echo -e "${RED}❌ Failed: ${#FAILED_SCENARIOS[@]}${NC}"

echo ""
if [ ${#PASSED_SCENARIOS[@]} -gt 0 ]; then
    echo -e "${GREEN}✅ PASSED SCENARIOS:${NC}"
    for scenario in "${PASSED_SCENARIOS[@]}"; do
        echo -e "   • $scenario"
    done
fi

if [ ${#FAILED_SCENARIOS[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}❌ FAILED SCENARIOS:${NC}"
    for scenario in "${FAILED_SCENARIOS[@]}"; do
        echo -e "   • $scenario"
    done
fi

echo -e "${BLUE}========================================${NC}"

# Optional harness contract checks (disabled by default)
if [[ "${INCLUDE_HARNESS_CONTRACT_TESTS:-false}" == "true" ]]; then
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}🧩 Running harness contract checks${NC}"
    echo -e "${BLUE}========================================${NC}"
    if ./scripts/run-harness-contract-tests.sh; then
        echo -e "${GREEN}✅ harness-contract: PASSED${NC}"
    else
        echo -e "${RED}❌ harness-contract: FAILED${NC}"
        if [ "$CONTINUE_ON_ERROR" = false ]; then
            exit 1
        fi
    fi
fi

# Exit with appropriate code
if [ ${#FAILED_SCENARIOS[@]} -eq 0 ]; then
    echo -e "${GREEN}🎉 ALL TESTS PASSED!${NC}"
    exit 0
else
    echo -e "${RED}💥 SOME TESTS FAILED!${NC}"
    exit 1
fi
