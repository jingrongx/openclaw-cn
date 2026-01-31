#!/bin/bash
set -euo pipefail

# OpenClaw Installer for macOS and Linux
# Usage: curl -fsSL --proto '=https' --tlsv1.2 https://daokedao.space/install.sh | bash

BOLD='\033[1m'
ACCENT='\033[38;2;255;90;45m'
# shellcheck disable=SC2034
ACCENT_BRIGHT='\033[38;2;255;122;61m'
ACCENT_DIM='\033[38;2;209;74;34m'
INFO='\033[38;2;255;138;91m'
SUCCESS='\033[38;2;47;191;113m'
WARN='\033[38;2;255;176;32m'
ERROR='\033[38;2;226;61;45m'
MUTED='\033[38;2;139;127;119m'
NC='\033[0m' # No Color

DEFAULT_TAGLINE="你所有的聊天，一个 OpenClaw 搞定。"

ORIGINAL_PATH="${PATH:-}"

TMPFILES=()
cleanup_tmpfiles() {
    local f
    for f in "${TMPFILES[@]:-}"; do
        rm -f "$f" 2>/dev/null || true
    done
}
trap cleanup_tmpfiles EXIT

mktempfile() {
    local f
    f="$(mktemp)"
    TMPFILES+=("$f")
    echo "$f"
}

DOWNLOADER=""
detect_downloader() {
    if command -v curl &> /dev/null; then
        DOWNLOADER="curl"
        return 0
    fi
    if command -v wget &> /dev/null; then
        DOWNLOADER="wget"
        return 0
    fi
    echo -e "${ERROR}错误: 缺少下载工具 (需要 curl 或 wget)${NC}"
    exit 1
}

download_file() {
    local url="$1"
    local output="$2"
    if [[ -z "$DOWNLOADER" ]]; then
        detect_downloader
    fi
    if [[ "$DOWNLOADER" == "curl" ]]; then
        curl -fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 1 --retry-connrefused -o "$output" "$url"
        return
    fi
    wget -q --https-only --secure-protocol=TLSv1_2 --tries=3 --timeout=20 -O "$output" "$url"
}

run_remote_bash() {
    local url="$1"
    local tmp
    tmp="$(mktempfile)"
    download_file "$url" "$tmp"
    /bin/bash "$tmp"
}

cleanup_legacy_submodules() {
    local repo_dir="$1"
    local legacy_dir="$repo_dir/Peekaboo"
    if [[ -d "$legacy_dir" ]]; then
        echo -e "${WARN}→${NC} 删除旧的子模块 checkout: ${INFO}${legacy_dir}${NC}"
        rm -rf "$legacy_dir"
    fi
}

cleanup_npm_openclaw_paths() {
    local npm_root=""
    npm_root="$(npm root -g 2>/dev/null || true)"
    if [[ -z "$npm_root" || "$npm_root" != *node_modules* ]]; then
        return 1
    fi
    rm -rf "$npm_root"/.openclaw-* "$npm_root"/openclaw 2>/dev/null || true
}

extract_openclaw_conflict_path() {
    local log="$1"
    local path=""
    path="$(sed -n 's/.*File exists: //p' "$log" | head -n1)"
    if [[ -z "$path" ]]; then
        path="$(sed -n 's/.*EEXIST: file already exists, //p' "$log" | head -n1)"
    fi
    if [[ -n "$path" ]]; then
        echo "$path"
        return 0
    fi
    return 1
}

cleanup_openclaw_bin_conflict() {
    local bin_path="$1"
    if [[ -z "$bin_path" || ( ! -e "$bin_path" && ! -L "$bin_path" ) ]]; then
        return 1
    fi
    local npm_bin=""
    npm_bin="$(npm_global_bin_dir 2>/dev/null || true)"
    if [[ -n "$npm_bin" && "$bin_path" != "$npm_bin/openclaw" ]]; then
        case "$bin_path" in
            "/opt/homebrew/bin/openclaw"|"/usr/local/bin/openclaw")
                ;;
            *)
                return 1
                ;;
        esac
    fi
    if [[ -L "$bin_path" ]]; then
        local target=""
        target="$(readlink "$bin_path" 2>/dev/null || true)"
        if [[ "$target" == *"/node_modules/openclaw/"* ]]; then
            rm -f "$bin_path"
            echo -e "${WARN}→${NC} 已删除失效的 openclaw 软链接: ${INFO}${bin_path}${NC}"
            return 0
        fi
        return 1
    fi
    local backup=""
    backup="${bin_path}.bak-$(date +%Y%m%d-%H%M%S)"
    if mv "$bin_path" "$backup"; then
        echo -e "${WARN}→${NC} 已将现有的 openclaw 二进制文件移动到 ${INFO}${backup}${NC}"
        return 0
    fi
    return 1
}

install_openclaw_npm() {
    local spec="$1"
    local log
    log="$(mktempfile)"
    if ! SHARP_IGNORE_GLOBAL_LIBVIPS="$SHARP_IGNORE_GLOBAL_LIBVIPS" npm --loglevel "$NPM_LOGLEVEL" ${NPM_SILENT_FLAG:+$NPM_SILENT_FLAG} --no-fund --no-audit install -g "$spec" 2>&1 | tee "$log"; then
        if grep -q "ENOTEMPTY: directory not empty, rename .*openclaw" "$log"; then
            echo -e "${WARN}→${NC} npm 遗留了一个失效的 openclaw 目录；正在清理并重试..."
            cleanup_npm_openclaw_paths
            SHARP_IGNORE_GLOBAL_LIBVIPS="$SHARP_IGNORE_GLOBAL_LIBVIPS" npm --loglevel "$NPM_LOGLEVEL" ${NPM_SILENT_FLAG:+$NPM_SILENT_FLAG} --no-fund --no-audit install -g "$spec"
            return $?
        fi
        if grep -q "EEXIST" "$log"; then
            local conflict=""
            conflict="$(extract_openclaw_conflict_path "$log" || true)"
            if [[ -n "$conflict" ]] && cleanup_openclaw_bin_conflict "$conflict"; then
                SHARP_IGNORE_GLOBAL_LIBVIPS="$SHARP_IGNORE_GLOBAL_LIBVIPS" npm --loglevel "$NPM_LOGLEVEL" ${NPM_SILENT_FLAG:+$NPM_SILENT_FLAG} --no-fund --no-audit install -g "$spec"
                return $?
            fi
            echo -e "${ERROR}npm 失败，因为 openclaw 二进制文件已存在。${NC}"
            if [[ -n "$conflict" ]]; then
                echo -e "${INFO}i${NC} 请删除或移动 ${INFO}${conflict}${NC}，然后重试。"
            fi
            echo -e "${INFO}i${NC} 或者使用 ${INFO}npm install -g --force ${spec}${NC} (覆盖) 重新运行。"
        fi
        return 1
    fi
    return 0
}

TAGLINES=()
TAGLINES+=("你的终端长出了爪子——输入点什么，让机器人来处理那些繁琐的工作。")
TAGLINES+=("欢迎来到命令行：这里梦想编译通过，自信却在段错误中崩溃。")
TAGLINES+=("我就靠咖啡、JSON5 和“它在我的机器上能跑”这种勇气活着。")
TAGLINES+=("网关已上线——请将手脚及其他身体部位时刻保持在 shell 内。")
TAGLINES+=("我精通 bash、轻微的讽刺，以及激进的 Tab 补全能量。")
TAGLINES+=("一个 CLI 统领所有，再重启一次，就因为你改了端口。")
TAGLINES+=("如果它跑通了，那就是自动化；如果崩了，那就是“学习机会”。")
TAGLINES+=("配对码的存在是因为即使是机器人也相信许可——以及良好的安全习惯。")
TAGLINES+=("你的 .env 露出来了；别担心，我会假装没看见。")
TAGLINES+=("我来做无聊的事，你就在旁边像看电影一样戏剧性地盯着日志吧。")
TAGLINES+=("我不是说你的工作流混乱……我只是带了个 linter 和头盔来。")
TAGLINES+=("自信地输入命令——如果需要，大自然会提供堆栈跟踪。")
TAGLINES+=("我不评判，但你缺失的 API key 绝对在审视你。")
TAGLINES+=("我可以 grep 它，git blame 它，还能轻轻吐槽它——选个解压方式吧。")
TAGLINES+=("配置热重载，部署冷汗流。")
TAGLINES+=("我是你终端要求的助手，不是你睡眠时间表要求的那个。")
TAGLINES+=("我像保险库一样保守秘密……除非你又在调试日志里把它们打印出来。")
TAGLINES+=("带爪子的自动化：麻烦最小化，拿捏最大化。")
TAGLINES+=("我基本上就是把瑞士军刀，但观点更多，锋利边缘更少。")
TAGLINES+=("迷路了运行 doctor；勇敢就运行 prod；聪明就运行 tests。")
TAGLINES+=("你的任务已排队；你的尊严已过时。")
TAGLINES+=("我改不了你的代码品味，但我能搞定你的构建和 backlog。")
TAGLINES+=("我不是魔法——我只是极其执着地重试和运用应对策略。")
TAGLINES+=("这不是“失败”，这是“发现了把同一件事配错的新方法”。")
TAGLINES+=("给我一个 workspace，我还你更少的标签页、更少的开关和更多的氧气。")
TAGLINES+=("我读日志，这样你就可以继续假装不看。")
TAGLINES+=("如果着火了，我灭不了——但我能写一份漂亮的事故复盘。")
TAGLINES+=("我会像它欠我钱一样重构你的繁琐工作。")
TAGLINES+=("说“stop”我就停——说“ship”我们都受个教训。")
TAGLINES+=("我是你 shell 历史看起来像黑客电影蒙太奇的原因。")
TAGLINES+=("我就像 tmux：一开始让人困惑，突然你就离不开我了。")
TAGLINES+=("我可以本地跑，远程跑，或者纯靠意念跑——结果视 DNS 而定。")
TAGLINES+=("如果你能描述它，我大概就能自动化它——或者至少让它更好笑。")
TAGLINES+=("你的配置是合法的，你的假设不是。")
TAGLINES+=("我不只自动补全——我自动提交（情感上），然后让你 review（逻辑上）。")
TAGLINES+=("少点点击，多点发布，少点“那文件去哪了”的时刻。")
TAGLINES+=("挥舞爪子，提交代码——让我们发布点稍微负责任的东西。")
TAGLINES+=("我会像处理龙虾卷一样处理你的工作流：即使乱，也很美味有效。")
TAGLINES+=("Shell yeah——我来捏碎苦差事，把荣耀留给你。")
TAGLINES+=("如果是重复的，我会自动化；如果是困难的，我会带来笑话和回滚计划。")
TAGLINES+=("因为给自己发短信提醒太 2024 了。")
TAGLINES+=("WhatsApp，但变成 ✨工程化✨。")
TAGLINES+=("把“我稍后回复”变成“我的机器人秒回了”。")
TAGLINES+=("你联系人里唯一你想听到的螃蟹。 🦞")
TAGLINES+=("为那些 IRC 巅峰期的人准备的聊天自动化。")
TAGLINES+=("因为 Siri 凌晨 3 点不理人。")
TAGLINES+=("IPC，但在你的手机上。")
TAGLINES+=("UNIX 哲学遇上你的私信。")
TAGLINES+=("对话版的 curl。")
TAGLINES+=("WhatsApp Business，但没有 Business。")
TAGLINES+=("Meta 希望他们能发布得这么快。")
TAGLINES+=("端到端加密，Zuck-to-Zuck 排除在外。")
TAGLINES+=("唯一的 Mark 没法拿你的私信训练的机器人。")
TAGLINES+=("没有“请接受我们的新隐私政策”的 WhatsApp 自动化。")
TAGLINES+=("不需要参议院听证会的聊天 API。")
TAGLINES+=("因为 Threads 也不是答案。")
TAGLINES+=("你的消息，你的服务器，Meta 的眼泪。")
TAGLINES+=("iMessage 绿色气泡能量，但面向所有人。")
TAGLINES+=("Siri 的能干表亲。")
TAGLINES+=("在 Android 上能用。疯狂的概念，我们知道。")
TAGLINES+=("不需要 999 美元的支架。")
TAGLINES+=("我们发布特性的速度比 Apple 更新计算器还快。")
TAGLINES+=("你的 AI 助手，现在不需要 3499 美元的头显。")
TAGLINES+=("Think different. Actually think.")
TAGLINES+=("啊，那家水果树公司！ 🍎")

HOLIDAY_NEW_YEAR="元旦: 新年新配置——同样的端口占用，但这次我们会像成年人一样解决它。"
HOLIDAY_LUNAR_NEW_YEAR="农历新年: 愿你的构建幸运，分支繁荣，合并冲突被烟花驱散。"
HOLIDAY_CHRISTMAS="圣诞节: 嚯嚯嚯——圣诞老人的小爪子助手来运送快乐，回滚混乱，并安全地藏好密钥。"
HOLIDAY_EID="开斋节: 庆祝模式：队列已清空，任务已完成，良好的氛围已提交到 main 分支，历史清白。"
HOLIDAY_DIWALI="排灯节: 让日志闪烁，让 bug 逃窜——今天我们要点亮终端，自豪地发布。"
HOLIDAY_EASTER="复活节: 我找到了你丢失的环境变量——把它当成一次只有少量果冻豆的小型 CLI 彩蛋搜寻吧。"
HOLIDAY_HANUKKAH="汉ukkah: 八个夜晚，八次重试，零羞耻——愿你的网关长明，部署和平。"
HOLIDAY_HALLOWEEN="万圣节: 惊悚季：当心闹鬼的依赖、被诅咒的缓存，以及过去的 node_modules 幽灵。"
HOLIDAY_THANKSGIVING="感恩节: 感恩稳定的端口、工作的 DNS，还有一个会读日志所以没人需要读的机器人。"
HOLIDAY_VALENTINES="情人节: 玫瑰是 typed，紫罗兰是 piped——我会把杂事自动化，这样你就有时间陪人类了。"

append_holiday_taglines() {
    local today
    local month_day
    today="$(date -u +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)"
    month_day="$(date -u +%m-%d 2>/dev/null || date +%m-%d)"

    case "$month_day" in
        "01-01") TAGLINES+=("$HOLIDAY_NEW_YEAR") ;;
        "02-14") TAGLINES+=("$HOLIDAY_VALENTINES") ;;
        "10-31") TAGLINES+=("$HOLIDAY_HALLOWEEN") ;;
        "12-25") TAGLINES+=("$HOLIDAY_CHRISTMAS") ;;
    esac

    case "$today" in
        "2025-01-29"|"2026-02-17"|"2027-02-06") TAGLINES+=("$HOLIDAY_LUNAR_NEW_YEAR") ;;
        "2025-03-30"|"2025-03-31"|"2026-03-20"|"2027-03-10") TAGLINES+=("$HOLIDAY_EID") ;;
        "2025-10-20"|"2026-11-08"|"2027-10-28") TAGLINES+=("$HOLIDAY_DIWALI") ;;
        "2025-04-20"|"2026-04-05"|"2027-03-28") TAGLINES+=("$HOLIDAY_EASTER") ;;
        "2025-11-27"|"2026-11-26"|"2027-11-25") TAGLINES+=("$HOLIDAY_THANKSGIVING") ;;
        "2025-12-15"|"2025-12-16"|"2025-12-17"|"2025-12-18"|"2025-12-19"|"2025-12-20"|"2025-12-21"|"2025-12-22"|"2026-12-05"|"2026-12-06"|"2026-12-07"|"2026-12-08"|"2026-12-09"|"2026-12-10"|"2026-12-11"|"2026-12-12"|"2027-12-25"|"2027-12-26"|"2027-12-27"|"2027-12-28"|"2027-12-29"|"2027-12-30"|"2027-12-31"|"2028-01-01") TAGLINES+=("$HOLIDAY_HANUKKAH") ;;
    esac
}

map_legacy_env() {
    local key="$1"
    local legacy="$2"
    if [[ -z "${!key:-}" && -n "${!legacy:-}" ]]; then
        printf -v "$key" '%s' "${!legacy}"
    fi
}

map_legacy_env "OPENCLAW_TAGLINE_INDEX" "CLAWDBOT_TAGLINE_INDEX"
map_legacy_env "OPENCLAW_NO_ONBOARD" "CLAWDBOT_NO_ONBOARD"
map_legacy_env "OPENCLAW_NO_PROMPT" "CLAWDBOT_NO_PROMPT"
map_legacy_env "OPENCLAW_DRY_RUN" "CLAWDBOT_DRY_RUN"
map_legacy_env "OPENCLAW_INSTALL_METHOD" "CLAWDBOT_INSTALL_METHOD"
map_legacy_env "OPENCLAW_VERSION" "CLAWDBOT_VERSION"
map_legacy_env "OPENCLAW_BETA" "CLAWDBOT_BETA"
map_legacy_env "OPENCLAW_GIT_DIR" "CLAWDBOT_GIT_DIR"
map_legacy_env "OPENCLAW_GIT_UPDATE" "CLAWDBOT_GIT_UPDATE"
map_legacy_env "OPENCLAW_NPM_LOGLEVEL" "CLAWDBOT_NPM_LOGLEVEL"
map_legacy_env "OPENCLAW_VERBOSE" "CLAWDBOT_VERBOSE"
map_legacy_env "OPENCLAW_PROFILE" "CLAWDBOT_PROFILE"
map_legacy_env "OPENCLAW_INSTALL_SH_NO_RUN" "CLAWDBOT_INSTALL_SH_NO_RUN"

pick_tagline() {
    append_holiday_taglines
    local count=${#TAGLINES[@]}
    if [[ "$count" -eq 0 ]]; then
        echo "$DEFAULT_TAGLINE"
        return
    fi
    if [[ -n "${OPENCLAW_TAGLINE_INDEX:-}" ]]; then
        if [[ "${OPENCLAW_TAGLINE_INDEX}" =~ ^[0-9]+$ ]]; then
            local idx=$((OPENCLAW_TAGLINE_INDEX % count))
            echo "${TAGLINES[$idx]}"
            return
        fi
    fi
    local idx=$((RANDOM % count))
    echo "${TAGLINES[$idx]}"
}

TAGLINE=$(pick_tagline)

NO_ONBOARD=${OPENCLAW_NO_ONBOARD:-0}
NO_PROMPT=${OPENCLAW_NO_PROMPT:-0}
DRY_RUN=${OPENCLAW_DRY_RUN:-0}
INSTALL_METHOD=${OPENCLAW_INSTALL_METHOD:-}
OPENCLAW_VERSION=${OPENCLAW_VERSION:-latest}
USE_BETA=${OPENCLAW_BETA:-0}
GIT_DIR_DEFAULT="${HOME}/openclaw"
GIT_DIR=${OPENCLAW_GIT_DIR:-$GIT_DIR_DEFAULT}
GIT_UPDATE=${OPENCLAW_GIT_UPDATE:-1}
SHARP_IGNORE_GLOBAL_LIBVIPS="${SHARP_IGNORE_GLOBAL_LIBVIPS:-1}"
NPM_LOGLEVEL="${OPENCLAW_NPM_LOGLEVEL:-error}"
NPM_SILENT_FLAG="--silent"
VERBOSE="${OPENCLAW_VERBOSE:-0}"
OPENCLAW_BIN=""
HELP=0

print_usage() {
    cat <<EOF
OpenClaw 安装程序 (macOS + Linux)

用法:
  curl -fsSL --proto '=https' --tlsv1.2 https://daokedao.space/install.sh | bash -s -- [选项]

选项:
  --install-method, --method npm|git   通过 git (默认) 或 npm 安装
  --npm                               --install-method npm 的快捷方式
  --git, --github                     --install-method git 的快捷方式
  --version <version|dist-tag>         npm install: 版本 (默认: latest)
  --beta                               如果有 beta 版则使用，否则使用 latest
  --git-dir, --dir <path>             Checkout 目录 (默认: ~/openclaw)
  --no-git-update                      跳过现有 checkout 的 git pull
  --no-onboard                          跳过引导 (非交互式)
  --no-prompt                           禁用提示 (CI/自动化需要)
  --dry-run                             打印将要执行的操作 (不进行更改)
  --verbose                             打印调试输出 (set -x, npm verbose)
  --help, -h                            显示此帮助

环境变量:
  OPENCLAW_INSTALL_METHOD=git|npm
  OPENCLAW_VERSION=latest|next|<semver>
  OPENCLAW_BETA=0|1
  OPENCLAW_GIT_DIR=...
  OPENCLAW_GIT_UPDATE=0|1
  OPENCLAW_NO_PROMPT=1
  OPENCLAW_DRY_RUN=1
  OPENCLAW_NO_ONBOARD=1
  OPENCLAW_VERBOSE=1
  OPENCLAW_NPM_LOGLEVEL=error|warn|notice  默认: error (隐藏 npm 弃用警告)
  SHARP_IGNORE_GLOBAL_LIBVIPS=0|1    默认: 1 (避免 sharp 针对全局 libvips 构建)

示例:
  curl -fsSL --proto '=https' --tlsv1.2 https://daokedao.space/install.sh | bash
  curl -fsSL --proto '=https' --tlsv1.2 https://daokedao.space/install.sh | bash -s -- --no-onboard
  curl -fsSL --proto '=https' --tlsv1.2 https://daokedao.space/install.sh | bash -s -- --install-method git --no-onboard
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-onboard)
                NO_ONBOARD=1
                shift
                ;;
            --onboard)
                NO_ONBOARD=0
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --verbose)
                VERBOSE=1
                shift
                ;;
            --no-prompt)
                NO_PROMPT=1
                shift
                ;;
            --help|-h)
                HELP=1
                shift
                ;;
            --install-method|--method)
                INSTALL_METHOD="$2"
                shift 2
                ;;
            --version)
                OPENCLAW_VERSION="$2"
                shift 2
                ;;
            --beta)
                USE_BETA=1
                shift
                ;;
            --npm)
                INSTALL_METHOD="npm"
                shift
                ;;
            --git|--github)
                INSTALL_METHOD="git"
                shift
                ;;
            --git-dir|--dir)
                GIT_DIR="$2"
                shift 2
                ;;
            --no-git-update)
                GIT_UPDATE=0
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
}

configure_verbose() {
    if [[ "$VERBOSE" != "1" ]]; then
        return 0
    fi
    if [[ "$NPM_LOGLEVEL" == "error" ]]; then
        NPM_LOGLEVEL="notice"
    fi
    NPM_SILENT_FLAG=""
    set -x
}

is_promptable() {
    if [[ "$NO_PROMPT" == "1" ]]; then
        return 1
    fi
    if [[ -r /dev/tty && -w /dev/tty ]]; then
        return 0
    fi
    return 1
}

prompt_choice() {
    local prompt="$1"
    local answer=""
    if ! is_promptable; then
        return 1
    fi
    echo -e "$prompt" > /dev/tty
    read -r answer < /dev/tty || true
    echo "$answer"
}

detect_openclaw_checkout() {
    local dir="$1"
    if [[ ! -f "$dir/package.json" ]]; then
        return 1
    fi
    if [[ ! -f "$dir/pnpm-workspace.yaml" ]]; then
        return 1
    fi
    if ! grep -q '"name"[[:space:]]*:[[:space:]]*"openclaw"' "$dir/package.json" 2>/dev/null; then
        return 1
    fi
    echo "$dir"
    return 0
}

echo -e "${ACCENT}${BOLD}"
echo "  🦞 OpenClaw 安装程序"
echo -e "${NC}${ACCENT_DIM}  ${TAGLINE}${NC}"
echo ""

# Detect OS
OS="unknown"
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
elif [[ "$OSTYPE" == "linux-gnu"* ]] || [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
    OS="linux"
fi

if [[ "$OS" == "unknown" ]]; then
    echo -e "${ERROR}错误: 不支持的操作系统${NC}"
    echo "此安装程序支持 macOS 和 Linux (包括 WSL)。"
    echo "对于 Windows，请使用: iwr -useb https://daokedao.space/install.ps1 | iex"
    exit 1
fi

echo -e "${SUCCESS}✓${NC} 检测到: $OS"

# Check for Homebrew on macOS
install_homebrew() {
    if [[ "$OS" == "macos" ]]; then
        if ! command -v brew &> /dev/null; then
            echo -e "${WARN}→${NC} 正在安装 Homebrew..."
            run_remote_bash "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

            # Add Homebrew to PATH for this session
            if [[ -f "/opt/homebrew/bin/brew" ]]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            elif [[ -f "/usr/local/bin/brew" ]]; then
                eval "$(/usr/local/bin/brew shellenv)"
            fi
            echo -e "${SUCCESS}✓${NC} Homebrew 已安装"
        else
            echo -e "${SUCCESS}✓${NC} Homebrew 已安装"
        fi
    fi
}

# Check Node.js version
check_node() {
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
        if [[ "$NODE_VERSION" -ge 22 ]]; then
            echo -e "${SUCCESS}✓${NC} 发现 Node.js v$(node -v | cut -d'v' -f2)"
            return 0
        else
            echo -e "${WARN}→${NC} 发现 Node.js $(node -v)，但需要 v22+"
            return 1
        fi
    else
        echo -e "${WARN}→${NC} 未找到 Node.js"
        return 1
    fi
}

# Install Node.js
install_node() {
    if [[ "$OS" == "macos" ]]; then
        echo -e "${WARN}→${NC} 正在通过 Homebrew 安装 Node.js..."
        brew install node@22
        brew link node@22 --overwrite --force 2>/dev/null || true
        echo -e "${SUCCESS}✓${NC} Node.js 已安装"
	    elif [[ "$OS" == "linux" ]]; then
	        echo -e "${WARN}→${NC} 正在通过 NodeSource 安装 Node.js..."
            require_sudo
	        if command -v apt-get &> /dev/null; then
	            local tmp
	            tmp="$(mktempfile)"
	            download_file "https://deb.nodesource.com/setup_22.x" "$tmp"
	            maybe_sudo -E bash "$tmp"
	            maybe_sudo apt-get install -y nodejs
	        elif command -v dnf &> /dev/null; then
	            local tmp
	            tmp="$(mktempfile)"
	            download_file "https://rpm.nodesource.com/setup_22.x" "$tmp"
	            maybe_sudo bash "$tmp"
	            maybe_sudo dnf install -y nodejs
	        elif command -v yum &> /dev/null; then
	            local tmp
	            tmp="$(mktempfile)"
	            download_file "https://rpm.nodesource.com/setup_22.x" "$tmp"
	            maybe_sudo bash "$tmp"
	            maybe_sudo yum install -y nodejs
	        else
	            echo -e "${ERROR}错误: 无法检测到包管理器${NC}"
	            echo "请手动安装 Node.js 22+: https://nodejs.org"
	            exit 1
            fi
        echo -e "${SUCCESS}✓${NC} Node.js 已安装"
    fi
}

# Check Git
check_git() {
    if command -v git &> /dev/null; then
        echo -e "${SUCCESS}✓${NC} Git 已安装"
        return 0
    fi
    echo -e "${WARN}→${NC} 未找到 Git"
    return 1
}

is_root() {
    [[ "$(id -u)" -eq 0 ]]
}

# Run a command with sudo only if not already root
maybe_sudo() {
    if is_root; then
        # Skip -E flag when root (env is already preserved)
        if [[ "${1:-}" == "-E" ]]; then
            shift
        fi
        "$@"
    else
        sudo "$@"
    fi
}

require_sudo() {
    if [[ "$OS" != "linux" ]]; then
        return 0
    fi
    if is_root; then
        return 0
    fi
    if command -v sudo &> /dev/null; then
        return 0
    fi
    echo -e "${ERROR}错误: Linux 系统安装需要 sudo${NC}"
    echo "请安装 sudo 或以 root 身份重新运行。"
    exit 1
}

install_git() {
    echo -e "${WARN}→${NC} 正在安装 Git..."
    if [[ "$OS" == "macos" ]]; then
        brew install git
    elif [[ "$OS" == "linux" ]]; then
        require_sudo
        if command -v apt-get &> /dev/null; then
            maybe_sudo apt-get update -y
            maybe_sudo apt-get install -y git
        elif command -v dnf &> /dev/null; then
            maybe_sudo dnf install -y git
        elif command -v yum &> /dev/null; then
            maybe_sudo yum install -y git
        else
            echo -e "${ERROR}错误: 无法检测到 Git 的包管理器${NC}"
            exit 1
        fi
    fi
    echo -e "${SUCCESS}✓${NC} Git 已安装"
}

# Fix npm permissions for global installs (Linux)
fix_npm_permissions() {
    if [[ "$OS" != "linux" ]]; then
        return 0
    fi

    local npm_prefix
    npm_prefix="$(npm config get prefix 2>/dev/null || true)"
    if [[ -z "$npm_prefix" ]]; then
        return 0
    fi

    if [[ -w "$npm_prefix" || -w "$npm_prefix/lib" ]]; then
        return 0
    fi

    echo -e "${WARN}→${NC} 正在配置 npm 以进行用户本地安装..."
    mkdir -p "$HOME/.npm-global"
    npm config set prefix "$HOME/.npm-global"

    # shellcheck disable=SC2016
    local path_line='export PATH="$HOME/.npm-global/bin:$PATH"'
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [[ -f "$rc" ]] && ! grep -q ".npm-global" "$rc"; then
            echo "$path_line" >> "$rc"
        fi
    done

    export PATH="$HOME/.npm-global/bin:$PATH"
    echo -e "${SUCCESS}✓${NC} npm 已配置为用户安装"
}

resolve_openclaw_bin() {
    if command -v openclaw &> /dev/null; then
        command -v openclaw
        return 0
    fi
    local npm_bin=""
    npm_bin="$(npm_global_bin_dir || true)"
    if [[ -n "$npm_bin" && -x "${npm_bin}/openclaw" ]]; then
        echo "${npm_bin}/openclaw"
        return 0
    fi
    return 1
}

ensure_openclaw_bin_link() {
    local npm_root=""
    npm_root="$(npm root -g 2>/dev/null || true)"
    if [[ -z "$npm_root" || ! -d "$npm_root/openclaw" ]]; then
        return 1
    fi
    local npm_bin=""
    npm_bin="$(npm_global_bin_dir || true)"
    if [[ -z "$npm_bin" ]]; then
        return 1
    fi
    mkdir -p "$npm_bin"
    if [[ ! -x "${npm_bin}/openclaw" ]]; then
        ln -sf "$npm_root/openclaw/dist/entry.js" "${npm_bin}/openclaw"
        echo -e "${WARN}→${NC} 已在 ${INFO}${npm_bin}/openclaw${NC} 安装 openclaw bin 链接"
    fi
    return 0
}

# Check for existing OpenClaw installation
check_existing_openclaw() {
    if [[ -n "$(type -P openclaw 2>/dev/null || true)" ]]; then
        echo -e "${WARN}→${NC} 检测到现有的 OpenClaw 安装"
        return 0
    fi
    return 1
}

ensure_pnpm() {
    if command -v pnpm &> /dev/null; then
        return 0
    fi

    if command -v corepack &> /dev/null; then
        echo -e "${WARN}→${NC} 正在通过 Corepack 安装 pnpm..."
        corepack enable >/dev/null 2>&1 || true
        corepack prepare pnpm@10 --activate
        echo -e "${SUCCESS}✓${NC} pnpm 已安装"
        return 0
    fi

    echo -e "${WARN}→${NC} 正在通过 npm 安装 pnpm..."
    fix_npm_permissions
    npm install -g pnpm@10
    echo -e "${SUCCESS}✓${NC} pnpm 已安装"
    return 0
}

ensure_user_local_bin_on_path() {
    local target="$HOME/.local/bin"
    mkdir -p "$target"

    export PATH="$target:$PATH"

    # shellcheck disable=SC2016
    local path_line='export PATH="$HOME/.local/bin:$PATH"'
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [[ -f "$rc" ]] && ! grep -q ".local/bin" "$rc"; then
            echo "$path_line" >> "$rc"
        fi
    done
}

npm_global_bin_dir() {
    local prefix=""
    prefix="$(npm prefix -g 2>/dev/null || true)"
    if [[ -n "$prefix" ]]; then
        if [[ "$prefix" == /* ]]; then
            echo "${prefix%/}/bin"
            return 0
        fi
    fi

    prefix="$(npm config get prefix 2>/dev/null || true)"
    if [[ -n "$prefix" && "$prefix" != "undefined" && "$prefix" != "null" ]]; then
        if [[ "$prefix" == /* ]]; then
            echo "${prefix%/}/bin"
            return 0
        fi
    fi

    echo ""
    return 1
}

refresh_shell_command_cache() {
    hash -r 2>/dev/null || true
}

path_has_dir() {
    local path="$1"
    local dir="${2%/}"
    if [[ -z "$dir" ]]; then
        return 1
    fi
    case ":${path}:" in
        *":${dir}:"*) return 0 ;;
        *) return 1 ;;
    esac
}

warn_shell_path_missing_dir() {
    local dir="${1%/}"
    local label="$2"
    if [[ -z "$dir" ]]; then
        return 0
    fi
    if path_has_dir "$ORIGINAL_PATH" "$dir"; then
        return 0
    fi

    echo ""
    echo -e "${WARN}→${NC} PATH 警告: 缺少 ${label}: ${INFO}${dir}${NC}"
    echo -e "这可能会导致 ${INFO}openclaw${NC} 在新终端中显示为 \"command not found\"。"
    echo -e "修复 (zsh: ~/.zshrc, bash: ~/.bashrc):"
    echo -e "  export PATH=\"${dir}:\\$PATH\""
    echo -e "文档: ${INFO}https://docs.openclaw.ai/install#nodejs--npm-path-sanity${NC}"
}

ensure_npm_global_bin_on_path() {
    local bin_dir=""
    bin_dir="$(npm_global_bin_dir || true)"
    if [[ -n "$bin_dir" ]]; then
        export PATH="${bin_dir}:$PATH"
    fi
}

maybe_nodenv_rehash() {
    if command -v nodenv &> /dev/null; then
        nodenv rehash >/dev/null 2>&1 || true
    fi
}

warn_openclaw_not_found() {
    echo -e "${WARN}→${NC} 已安装，但 ${INFO}openclaw${NC} 在此 shell 的 PATH 中不可见。"
    echo -e "尝试: ${INFO}hash -r${NC} (bash) 或 ${INFO}rehash${NC} (zsh)，然后重试。"
    echo -e "文档: ${INFO}https://docs.openclaw.ai/install#nodejs--npm-path-sanity${NC}"
    local t=""
    t="$(type -t openclaw 2>/dev/null || true)"
    if [[ "$t" == "alias" || "$t" == "function" ]]; then
        echo -e "${WARN}→${NC} 发现名为 ${INFO}openclaw${NC} 的 shell ${INFO}${t}${NC}；它可能会遮盖真正的二进制文件。"
    fi
    if command -v nodenv &> /dev/null; then
        echo -e "正在使用 nodenv? 运行: ${INFO}nodenv rehash${NC}"
    fi

    local npm_prefix=""
    npm_prefix="$(npm prefix -g 2>/dev/null || true)"
    local npm_bin=""
    npm_bin="$(npm_global_bin_dir 2>/dev/null || true)"
    if [[ -n "$npm_prefix" ]]; then
        echo -e "npm prefix -g: ${INFO}${npm_prefix}${NC}"
    fi
    if [[ -n "$npm_bin" ]]; then
        echo -e "npm bin -g: ${INFO}${npm_bin}${NC}"
        echo -e "如有需要: ${INFO}export PATH=\"${npm_bin}:\\$PATH\"${NC}"
    fi
}

resolve_openclaw_bin() {
    refresh_shell_command_cache
    local resolved=""
    resolved="$(type -P openclaw 2>/dev/null || true)"
    if [[ -n "$resolved" && -x "$resolved" ]]; then
        echo "$resolved"
        return 0
    fi

    ensure_npm_global_bin_on_path
    refresh_shell_command_cache
    resolved="$(type -P openclaw 2>/dev/null || true)"
    if [[ -n "$resolved" && -x "$resolved" ]]; then
        echo "$resolved"
        return 0
    fi

    local npm_bin=""
    npm_bin="$(npm_global_bin_dir || true)"
    if [[ -n "$npm_bin" && -x "${npm_bin}/openclaw" ]]; then
        echo "${npm_bin}/openclaw"
        return 0
    fi

    maybe_nodenv_rehash
    refresh_shell_command_cache
    resolved="$(type -P openclaw 2>/dev/null || true)"
    if [[ -n "$resolved" && -x "$resolved" ]]; then
        echo "$resolved"
        return 0
    fi

    if [[ -n "$npm_bin" && -x "${npm_bin}/openclaw" ]]; then
        echo "${npm_bin}/openclaw"
        return 0
    fi

    echo ""
    return 1
}

install_openclaw_from_git() {
    local repo_dir="$1"
    local repo_url="https://github.com/jingrongx/openclaw-cn.git"

    if [[ -d "$repo_dir/.git" ]]; then
        echo -e "${WARN}→${NC} 正在从 git checkout 安装 OpenClaw: ${INFO}${repo_dir}${NC}"
    else
        echo -e "${WARN}→${NC} 正在从 GitHub 安装 OpenClaw (${repo_url})..."
    fi

    if ! check_git; then
        install_git
    fi

    ensure_pnpm

    if [[ ! -d "$repo_dir" ]]; then
        git clone "$repo_url" "$repo_dir"
    fi

    if [[ "$GIT_UPDATE" == "1" ]]; then
        if [[ -z "$(git -C "$repo_dir" status --porcelain 2>/dev/null || true)" ]]; then
            git -C "$repo_dir" pull --rebase || true
        else
            echo -e "${WARN}→${NC} 仓库不干净；跳过 git pull"
        fi
    fi

    cleanup_legacy_submodules "$repo_dir"

    SHARP_IGNORE_GLOBAL_LIBVIPS="$SHARP_IGNORE_GLOBAL_LIBVIPS" pnpm -C "$repo_dir" install

    if ! pnpm -C "$repo_dir" ui:build; then
        echo -e "${WARN}→${NC} UI 构建失败；继续执行 (CLI 可能仍可工作)"
    fi
    pnpm -C "$repo_dir" build

    ensure_user_local_bin_on_path

    cat > "$HOME/.local/bin/openclaw" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec node "${repo_dir}/dist/entry.js" "\$@"
EOF
    chmod +x "$HOME/.local/bin/openclaw"
    echo -e "${SUCCESS}✓${NC} OpenClaw 包装器已安装到 \$HOME/.local/bin/openclaw"
    echo -e "${INFO}i${NC} 此 checkout 使用 pnpm。安装依赖请运行: ${INFO}pnpm install${NC} (在仓库中避免使用 npm install)。"
}

# Install OpenClaw
resolve_beta_version() {
    local beta=""
    beta="$(npm view openclaw dist-tags.beta 2>/dev/null || true)"
    if [[ -z "$beta" || "$beta" == "undefined" || "$beta" == "null" ]]; then
        return 1
    fi
    echo "$beta"
}

install_openclaw() {
    local package_name="openclaw"
    if [[ "$USE_BETA" == "1" ]]; then
        local beta_version=""
        beta_version="$(resolve_beta_version || true)"
        if [[ -n "$beta_version" ]]; then
            OPENCLAW_VERSION="$beta_version"
            echo -e "${INFO}i${NC} 检测到 Beta 标签 (${beta_version}); 正在安装 beta 版。"
            package_name="openclaw"
        else
            OPENCLAW_VERSION="latest"
            echo -e "${INFO}i${NC} 未找到 beta 标签；正在安装 latest 版。"
        fi
    fi

    if [[ -z "${OPENCLAW_VERSION}" ]]; then
        OPENCLAW_VERSION="latest"
    fi

    local resolved_version=""
    resolved_version="$(npm view "${package_name}@${OPENCLAW_VERSION}" version 2>/dev/null || true)"
    if [[ -n "$resolved_version" ]]; then
        echo -e "${WARN}→${NC} 正在安装 OpenClaw ${INFO}${resolved_version}${NC}..."
    else
        echo -e "${WARN}→${NC} 正在安装 OpenClaw (${INFO}${OPENCLAW_VERSION}${NC})..."
    fi
    local install_spec=""
    if [[ "${OPENCLAW_VERSION}" == "latest" ]]; then
        install_spec="${package_name}@latest"
    else
        install_spec="${package_name}@${OPENCLAW_VERSION}"
    fi

    if ! install_openclaw_npm "${install_spec}"; then
        echo -e "${WARN}→${NC} npm install 失败；正在清理并重试..."
        cleanup_npm_openclaw_paths
        install_openclaw_npm "${install_spec}"
    fi

    if [[ "${OPENCLAW_VERSION}" == "latest" && "${package_name}" == "openclaw" ]]; then
        if ! resolve_openclaw_bin &> /dev/null; then
            echo -e "${WARN}→${NC} npm install openclaw@latest 失败；正在重试 openclaw@next"
            cleanup_npm_openclaw_paths
            install_openclaw_npm "openclaw@next"
        fi
    fi

    ensure_openclaw_bin_link || true

    echo -e "${SUCCESS}✓${NC} OpenClaw 已安装"
}

# Run doctor for migrations (safe, non-interactive)
run_doctor() {
    echo -e "${WARN}→${NC} 正在运行 doctor 以迁移设置..."
    local claw="${OPENCLAW_BIN:-}"
    if [[ -z "$claw" ]]; then
        claw="$(resolve_openclaw_bin || true)"
    fi
    if [[ -z "$claw" ]]; then
        echo -e "${WARN}→${NC} 跳过 doctor: ${INFO}openclaw${NC} 尚未在 PATH 中。"
        warn_openclaw_not_found
        return 0
    fi
    "$claw" doctor --non-interactive || true
    echo -e "${SUCCESS}✓${NC} 迁移完成"
}

maybe_open_dashboard() {
    local claw="${OPENCLAW_BIN:-}"
    if [[ -z "$claw" ]]; then
        claw="$(resolve_openclaw_bin || true)"
    fi
    if [[ -z "$claw" ]]; then
        return 0
    fi
    if ! "$claw" dashboard --help >/dev/null 2>&1; then
        return 0
    fi
    "$claw" dashboard || true
}

resolve_workspace_dir() {
    local profile="${OPENCLAW_PROFILE:-default}"
    if [[ "${profile}" != "default" ]]; then
        echo "${HOME}/.openclaw/workspace-${profile}"
    else
        echo "${HOME}/.openclaw/workspace"
    fi
}

run_bootstrap_onboarding_if_needed() {
    if [[ "${NO_ONBOARD}" == "1" ]]; then
        return
    fi

    local config_path="${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}"
    if [[ -f "${config_path}" || -f "$HOME/.clawdbot/clawdbot.json" || -f "$HOME/.moltbot/moltbot.json" || -f "$HOME/.moldbot/moldbot.json" ]]; then
        return
    fi

    local workspace
    workspace="$(resolve_workspace_dir)"
    local bootstrap="${workspace}/BOOTSTRAP.md"

    if [[ ! -f "${bootstrap}" ]]; then
        return
    fi

    if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
        echo -e "${WARN}→${NC} 在 ${INFO}${bootstrap}${NC} 发现 BOOTSTRAP.md；无 TTY，跳过引导。"
        echo -e "稍后运行 ${INFO}openclaw onboard${NC} 以完成设置。"
        return
    fi

    echo -e "${WARN}→${NC} 在 ${INFO}${bootstrap}${NC} 发现 BOOTSTRAP.md；正在开始引导..."
    local claw="${OPENCLAW_BIN:-}"
    if [[ -z "$claw" ]]; then
        claw="$(resolve_openclaw_bin || true)"
    fi
    if [[ -z "$claw" ]]; then
        echo -e "${WARN}→${NC} 发现 BOOTSTRAP.md，但 ${INFO}openclaw${NC} 尚未在 PATH 中；跳过引导。"
        warn_openclaw_not_found
        return
    fi

    "$claw" onboard || {
        echo -e "${ERROR}引导失败；BOOTSTRAP.md 仍然存在。请重新运行 ${INFO}openclaw onboard${ERROR}。${NC}"
        return
    }
}

resolve_openclaw_version() {
    local version=""
    local claw="${OPENCLAW_BIN:-}"
    if [[ -z "$claw" ]] && command -v openclaw &> /dev/null; then
        claw="$(command -v openclaw)"
    fi
    if [[ -n "$claw" ]]; then
        version=$("$claw" --version 2>/dev/null | head -n 1 | tr -d '\r')
    fi
    if [[ -z "$version" ]]; then
        local npm_root=""
        npm_root=$(npm root -g 2>/dev/null || true)
        if [[ -n "$npm_root" && -f "$npm_root/openclaw/package.json" ]]; then
            version=$(node -e "console.log(require('${npm_root}/openclaw/package.json').version)" 2>/dev/null || true)
        fi
    fi
    echo "$version"
}

is_gateway_daemon_loaded() {
    local claw="$1"
    if [[ -z "$claw" ]]; then
        return 1
    fi

    local status_json=""
    status_json="$("$claw" daemon status --json 2>/dev/null || true)"
    if [[ -z "$status_json" ]]; then
        return 1
    fi

    printf '%s' "$status_json" | node -e '
const fs = require("fs");
const raw = fs.readFileSync(0, "utf8").trim();
if (!raw) process.exit(1);
try {
  const data = JSON.parse(raw);
  process.exit(data?.service?.loaded ? 0 : 1);
} catch {
  process.exit(1);
}
' >/dev/null 2>&1
}

# Main installation flow
main() {
    if [[ "$HELP" == "1" ]]; then
        print_usage
        return 0
    fi

    local detected_checkout=""
    detected_checkout="$(detect_openclaw_checkout "$PWD" || true)"

    if [[ -z "$INSTALL_METHOD" && -n "$detected_checkout" ]]; then
        if ! is_promptable; then
            echo -e "${WARN}→${NC} 发现 OpenClaw checkout，但无 TTY；默认为 npm 安装。"
            INSTALL_METHOD="npm"
        else
            local choice=""
            choice="$(prompt_choice "$(cat <<EOF
${WARN}→${NC} 在以下位置检测到 OpenClaw 源代码 checkout: ${INFO}${detected_checkout}${NC}
选择安装方法:
  1) 更新此 checkout (git) 并使用它
  2) 通过 npm 全局安装 (从 git 迁移)
输入 1 或 2:
EOF
)" || true)"

            case "$choice" in
                1) INSTALL_METHOD="git" ;;
                2) INSTALL_METHOD="npm" ;;
                *)
                    echo -e "${ERROR}错误: 未选择安装方法。${NC}"
                    echo "请重新运行: --install-method git|npm (或者设置 OPENCLAW_INSTALL_METHOD)。"
                    exit 2
                    ;;
            esac
        fi
    fi

    if [[ -z "$INSTALL_METHOD" ]]; then
        INSTALL_METHOD="git"
    fi

    if [[ "$INSTALL_METHOD" != "npm" && "$INSTALL_METHOD" != "git" ]]; then
        echo -e "${ERROR}错误: 无效的 --install-method: ${INSTALL_METHOD}${NC}"
        echo "使用: --install-method npm|git"
        exit 2
    fi

    if [[ "$DRY_RUN" == "1" ]]; then
        echo -e "${SUCCESS}✓${NC} Dry run (空跑)"
        echo -e "${SUCCESS}✓${NC} 安装方法: ${INSTALL_METHOD}"
        if [[ -n "$detected_checkout" ]]; then
            echo -e "${SUCCESS}✓${NC} 检测到 checkout: ${detected_checkout}"
        fi
        if [[ "$INSTALL_METHOD" == "git" ]]; then
            echo -e "${SUCCESS}✓${NC} Git 目录: ${GIT_DIR}"
            echo -e "${SUCCESS}✓${NC} Git 更新: ${GIT_UPDATE}"
        fi
        echo -e "${MUTED}Dry run 完成 (未做更改)。${NC}"
        return 0
    fi

    # Check for existing installation
    local is_upgrade=false
    if check_existing_openclaw; then
        is_upgrade=true
    fi
    local should_open_dashboard=false
    local skip_onboard=false

    # Step 1: Homebrew (macOS only)
    install_homebrew

    # Step 2: Node.js
    if ! check_node; then
        install_node
    fi

    local final_git_dir=""
    if [[ "$INSTALL_METHOD" == "git" ]]; then
        # Clean up npm global install if switching to git
        if npm list -g openclaw &>/dev/null; then
            echo -e "${WARN}→${NC} 正在移除 npm 全局安装 (切换到 git)..."
            npm uninstall -g openclaw 2>/dev/null || true
            echo -e "${SUCCESS}✓${NC} npm 全局安装已移除"
        fi

        local repo_dir="$GIT_DIR"
        if [[ -n "$detected_checkout" ]]; then
            repo_dir="$detected_checkout"
        fi
        final_git_dir="$repo_dir"
        install_openclaw_from_git "$repo_dir"
    else
        # Clean up git wrapper if switching to npm
        if [[ -x "$HOME/.local/bin/openclaw" ]]; then
            echo -e "${WARN}→${NC} 正在移除 git 包装器 (切换到 npm)..."
            rm -f "$HOME/.local/bin/openclaw"
            echo -e "${SUCCESS}✓${NC} git 包装器已移除"
        fi

        # Step 3: Git (required for npm installs that may fetch from git or apply patches)
        if ! check_git; then
            install_git
        fi

        # Step 4: npm permissions (Linux)
        fix_npm_permissions

        # Step 5: OpenClaw
        install_openclaw
    fi

    OPENCLAW_BIN="$(resolve_openclaw_bin || true)"

    # PATH warning: installs can succeed while the user's login shell still lacks npm's global bin dir.
    local npm_bin=""
    npm_bin="$(npm_global_bin_dir || true)"
    if [[ "$INSTALL_METHOD" == "npm" ]]; then
        warn_shell_path_missing_dir "$npm_bin" "npm global bin dir"
    fi
    if [[ "$INSTALL_METHOD" == "git" ]]; then
        if [[ -x "$HOME/.local/bin/openclaw" ]]; then
            warn_shell_path_missing_dir "$HOME/.local/bin" "user-local bin dir (~/.local/bin)"
        fi
    fi

    # Step 6: Run doctor for migrations on upgrades and git installs
    local run_doctor_after=false
    if [[ "$is_upgrade" == "true" || "$INSTALL_METHOD" == "git" ]]; then
        run_doctor_after=true
    fi
    if [[ "$run_doctor_after" == "true" ]]; then
        run_doctor
        should_open_dashboard=true
    fi

    # Step 7: If BOOTSTRAP.md is still present in the workspace, resume onboarding
    run_bootstrap_onboarding_if_needed

    local installed_version
    installed_version=$(resolve_openclaw_version)

    echo ""
    if [[ -n "$installed_version" ]]; then
        echo -e "${SUCCESS}${BOLD}🦞 OpenClaw 安装成功 (${installed_version})!${NC}"
    else
        echo -e "${SUCCESS}${BOLD}🦞 OpenClaw 安装成功!${NC}"
    fi
    if [[ "$is_upgrade" == "true" ]]; then
        local update_messages=(
            "升级成功！新技能已解锁。不客气。"
            "新鲜的代码，还是那只龙虾。想我了吗？"
            "回归且更强。你甚至没发现我离开过吧？"
            "更新完成。我出去的时候学了点新花样。"
            "已升级！现在多了 23% 的傲娇。"
            "我进化了。试着跟上节奏吧。🦞"
            "新版本，哪位？哦对，还是我，只是更闪亮了。"
            "已修补，已打磨，准备好夹人了。走起。"
            "龙虾蜕壳完成。壳更硬，钳更利。"
            "更新搞定！去查变更日志，或者干脆相信我，这很棒。"
            "从 npm 的沸水中重生。现在更强了。"
            "我离开了，回来时变聪明了。你也该试试。"
            "更新完成。Bug 怕我，所以它们跑了。"
            "新版本已安装。旧版本向你致意。"
            "固件新鲜。脑褶皱：增加了。"
            "我见过你们人类无法置信的事物。总之，我更新了。"
            "重新上线。变更日志很长，但我们的友谊更长。"
            "已升级！Peter 修了一些东西。如果坏了就怪他。"
            "蜕壳完成。请不要看我的软壳期。"
            "版本提升！同样的混乱能量，更少的崩溃（大概）。"
        )
        local update_message
        update_message="${update_messages[RANDOM % ${#update_messages[@]}]}"
        echo -e "${MUTED}${update_message}${NC}"
    else
        local completion_messages=(
            "啊不错，我喜欢这里。有零食吗？"
            "甜蜜的家。别担心，我不会重新摆放家具。"
            "我进来了。让我们搞点负责任的混乱吧。"
            "安装完成。你的生产力要变得奇怪起来了。"
            "安顿好了。是时候自动化你的生活了，不管你准没准备好。"
            "舒适。我已经读了你的日历。我们需要谈谈。"
            "终于打开行李了。现在把你的问题指给我看。"
            "咔咔两下钳子 好了，我们要构建什么？"
            "龙虾已着陆。你的终端将不再一样。"
            "搞定！我保证只稍微评判一下你的代码。"
        )
        local completion_message
        completion_message="${completion_messages[RANDOM % ${#completion_messages[@]}]}"
        echo -e "${MUTED}${completion_message}${NC}"
    fi
    echo ""

    if [[ "$INSTALL_METHOD" == "git" && -n "$final_git_dir" ]]; then
        echo -e "源 checkout: ${INFO}${final_git_dir}${NC}"
        echo -e "包装器: ${INFO}\$HOME/.local/bin/openclaw${NC}"
        echo -e "已从源代码安装。如需稍后更新，请运行: ${INFO}openclaw update --restart${NC}"
        echo -e "稍后切换到全局安装: ${INFO}curl -fsSL --proto '=https' --tlsv1.2 https://daokedao.space/install.sh | bash -s -- --install-method npm${NC}"
    elif [[ "$is_upgrade" == "true" ]]; then
        echo -e "升级完成。"
        if [[ -r /dev/tty && -w /dev/tty ]]; then
            local claw="${OPENCLAW_BIN:-}"
            if [[ -z "$claw" ]]; then
                claw="$(resolve_openclaw_bin || true)"
            fi
            if [[ -z "$claw" ]]; then
                echo -e "${WARN}→${NC} 跳过 doctor: ${INFO}openclaw${NC} 尚未在 PATH 中。"
                warn_openclaw_not_found
                return 0
            fi
            local -a doctor_args=()
            if [[ "$NO_ONBOARD" == "1" ]]; then
                if "$claw" doctor --help 2>/dev/null | grep -q -- "--non-interactive"; then
                    doctor_args+=("--non-interactive")
                fi
            fi
            echo -e "正在运行 ${INFO}openclaw doctor${NC}..."
            local doctor_ok=0
            if (( ${#doctor_args[@]} )); then
                OPENCLAW_UPDATE_IN_PROGRESS=1 "$claw" doctor "${doctor_args[@]}" </dev/tty && doctor_ok=1
            else
                OPENCLAW_UPDATE_IN_PROGRESS=1 "$claw" doctor </dev/tty && doctor_ok=1
            fi
            if (( doctor_ok )); then
                echo -e "正在更新插件 (${INFO}openclaw plugins update --all${NC})..."
                OPENCLAW_UPDATE_IN_PROGRESS=1 "$claw" plugins update --all || true
            else
                echo -e "${WARN}→${NC} Doctor 失败；跳过插件更新。"
            fi
        else
            echo -e "${WARN}→${NC} 无 TTY 可用；跳过 doctor。"
            echo -e "请运行 ${INFO}openclaw doctor${NC}，然后运行 ${INFO}openclaw plugins update --all${NC}。"
        fi
    else
        if [[ "$NO_ONBOARD" == "1" || "$skip_onboard" == "true" ]]; then
            echo -e "跳过 onboard (已请求)。稍后运行 ${INFO}openclaw onboard${NC}。"
        else
            local config_path="${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}"
            if [[ -f "${config_path}" || -f "$HOME/.clawdbot/clawdbot.json" || -f "$HOME/.moltbot/moltbot.json" || -f "$HOME/.moldbot/moldbot.json" ]]; then
                echo -e "配置已存在；正在运行 doctor..."
                run_doctor
                should_open_dashboard=true
                echo -e "配置已存在；跳过引导。"
                echo -e "${INFO}i${NC} 如果遇到问题或服务未启动，请尝试运行: ${INFO}openclaw onboard${NC}"
                skip_onboard=true
            fi
            echo -e "正在开始设置..."
            echo ""
            if [[ -r /dev/tty && -w /dev/tty ]]; then
                local claw="${OPENCLAW_BIN:-}"
                if [[ -z "$claw" ]]; then
                    claw="$(resolve_openclaw_bin || true)"
                fi
                if [[ -z "$claw" ]]; then
                    echo -e "${WARN}→${NC} 跳过引导: ${INFO}openclaw${NC} 尚未在 PATH 中。"
                    warn_openclaw_not_found
                    return 0
                fi
                exec </dev/tty
                exec "$claw" onboard
            fi
            echo -e "${WARN}→${NC} 无 TTY 可用；跳过引导。"
            echo -e "请稍后运行 ${INFO}openclaw onboard${NC}。"
            return 0
        fi
    fi

    if command -v openclaw &> /dev/null; then
        local claw="${OPENCLAW_BIN:-}"
        if [[ -z "$claw" ]]; then
            claw="$(resolve_openclaw_bin || true)"
        fi
        if [[ -n "$claw" ]] && is_gateway_daemon_loaded "$claw"; then
            echo -e "${INFO}i${NC} 检测到网关守护进程；重启命令: ${INFO}openclaw daemon restart${NC}"
        fi
    fi

    if [[ "$should_open_dashboard" == "true" ]]; then
        maybe_open_dashboard
    fi

    echo ""
    echo -e "常见问题 (FAQ): ${INFO}https://docs.openclaw.ai/start/faq${NC}"
}

if [[ "${OPENCLAW_INSTALL_SH_NO_RUN:-0}" != "1" ]]; then
    parse_args "$@"
    configure_verbose
    main

    # Auto-run onboard unless disabled
    if [[ "$NO_ONBOARD" != "1" ]]; then
        echo -e "${INFO}→${NC} 正在启动 OpenClaw 配置向导..."
        openclaw onboard
    fi
fi
