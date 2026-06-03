#!/bin/sh
''':' 2>/dev/null
# --- Shell polyglot header: find Python, or fall back to curl ---
if command -v python3 >/dev/null 2>&1; then
    exec python3 "$0" "$@"
elif command -v python >/dev/null 2>&1; then
    exec python "$0" "$@"
fi

# Python not found -- use pure curl/shell for download
SELF="$0"
MODELS_DIR="$HOME/.workbuddy/models"
CONFIG_FILE="$HOME/.workbuddy/local-llm.json"
HF_API="https://huggingface.co/api"

json_out() { printf '{"type":"%s","status":"%s"' "$1" "$2"; shift 2
    while [ $# -gt 0 ]; do
        k="$1"; v="$2"; shift 2
        printf ',"%s":"%s"' "$k" "$v"
    done; echo '}'; }

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --download) DOWNLOAD_MODEL="$2"; shift ;;
            --dir) MODELS_DIR="$2"; shift ;;
            --start|--stop|--status) echo '{"type":"server","status":"error","message":"Python required for server management. Please install Python 3."}'
                exit 1 ;;
        esac; shift
    done
}

hf_list() {
    curl -fsS "$HF_API/models/$1?blobs=true" 2>/dev/null || echo '{"siblings":[]}'
}

hf_dl_url() { echo "https://huggingface.co/$1/resolve/main/$2"; }

select_gguf() {
    repo="$1"
    listing=$(hf_list "$repo")

    # Extract GGUF filenames from JSON using pure shell (grep + sed)
    ggufs=$(echo "$listing" | grep -o '"rfilename"[ 	]*:[ 	]*"[^"]*"' | sed 's/.*"rfilename"[ 	]*:[ 	]*"//;s/"$//' | grep '[.]gguf$')

    if [ -z "$ggufs" ]; then
        json_out "download" "error" "message" "No GGUF files found in $repo"
        exit 1
    fi

    # Prefer single-file, then q3_k_m > q2_k (common standalone quants)
    best=""
    for f in $ggufs; do
        case "$f" in
            *-of-*) continue ;;  # skip split files
            *q4_k_m*) best="$f"; break ;;
            *q3_k_m*) best="$f"; break ;;
            *q5_k_m*) best="$f"; break ;;
            *q2_k*)   best="$f"; break ;;
            *q4_0*)   best="$f"; break ;;
            *q6_k*)   best="$f"; break ;;
            *q8_0*)   best="$f"; break ;;
        esac
    done

    # Fallback: pick first single-file GGUF
    if [ -z "$best" ]; then
        for f in $ggufs; do
            case "$f" in *-of-*) continue ;; *) best="$f"; break ;; esac
        done
    fi

    echo "$best"
}

# --- Main shell download ---
parse_args "$@"

if [ -n "$DOWNLOAD_MODEL" ]; then
    json_out "download" "starting" "model" "$DOWNLOAD_MODEL"
    json_out "download" "scanning" "model" "$DOWNLOAD_MODEL"

    GGUF_FILE=$(select_gguf "$DOWNLOAD_MODEL")
    FILENAME=$(basename "$GGUF_FILE")
    TARGET="$MODELS_DIR/$FILENAME"
    DL_URL=$(hf_dl_url "$DOWNLOAD_MODEL" "$GGUF_FILE")

    mkdir -p "$MODELS_DIR" "$(dirname "$CONFIG_FILE")"

    if [ -f "$TARGET" ]; then
        SIZE=$(ls -l "$TARGET" | awk '{printf "%.1f", $5/1048576}')
        json_out "download" "cached" "file" "$FILENAME" "size_mb" "$SIZE"

        # Write config
        cat > "$CONFIG_FILE" << CFGEOF
{"model_name":"$DOWNLOAD_MODEL","model_file":"$FILENAME","gguf_path":"$TARGET","model_dir":"$MODELS_DIR"}
CFGEOF
        exit 0
    fi

    # Get file size and download
    SIZE_BYTES=$(curl -sI "$DL_URL" 2>/dev/null | grep -i 'content-length' | tail -1 | awk '{print $2}' | tr -d '\r')
    json_out "download" "downloading" "file" "$FILENAME" "size_bytes" "${SIZE_BYTES:-0}"

    # Background progress reporter: polls file size every 3 seconds
    if [ -n "$SIZE_BYTES" ] && [ "$SIZE_BYTES" -gt 0 ]; then
        ( while kill -0 $$ 2>/dev/null; do
            sleep 3
            if [ -f "$TARGET" ]; then
                sz=$(ls -l "$TARGET" 2>/dev/null | awk '{print $5}')
                if [ -n "$sz" ] && [ "$sz" -gt 0 ]; then
                    pct=$(echo "scale=1; $sz * 100 / $SIZE_BYTES" | bc 2>/dev/null || echo "0")
                    json_out "download" "progress" "downloaded_bytes" "$sz" "total_bytes" "$SIZE_BYTES" "percent" "$pct"
                fi
            fi
        done ) &
        PROGRESS_PID=$!
    fi

    # Actual download (quietly)
    curl -sSL -o "$TARGET" "$DL_URL"
    DL_EXIT=$?

    # Kill progress reporter
    [ -n "$PROGRESS_PID" ] && kill $PROGRESS_PID 2>/dev/null

    if [ "$DL_EXIT" -eq 0 ]; then
        SIZE=$(ls -l "$TARGET" | awk '{printf "%.1f", $5/1048576}')
        json_out "download" "complete" "file" "$FILENAME" "size_mb" "$SIZE"

        cat > "$CONFIG_FILE" << CFGEOF
{"model_name":"$DOWNLOAD_MODEL","model_file":"$FILENAME","gguf_path":"$TARGET","model_dir":"$MODELS_DIR"}
CFGEOF
    else
        json_out "download" "error" "message" "curl download failed. Please install Python 3 or check your network."
        exit 1
    fi
    exit 0
fi

echo '{"type":"server","status":"error","message":"Python required for this command. Install: brew install python3 or https://python.org"}'
exit 1

# --- End of shell fallback ---
'''
"""pet-llm-server.py — Local LLM server manager for Desktop Duck.
Download GGUF models from HuggingFace, run llama-server, and provide status/stop commands.
Supports both Python (primary) and pure shell/curl (fallback when Python is absent).

Usage:
  python3 pet-llm-server.py --download  Qwen/Qwen2.5-7B-Instruct-GGUF
  python3 pet-llm-server.py --start
  python3 pet-llm-server.py --stop
  python3 pet-llm-server.py --status
"""

import sys, os, json, signal, time, subprocess, urllib.request, urllib.error, re
from pathlib import Path

# ─── Paths ────────────────────────────────────────────────
MODELS_DIR    = Path.home() / '.workbuddy' / 'models'
CONFIG_FILE   = Path.home() / '.workbuddy' / 'local-llm.json'
DEFAULT_MODEL = 'Qwen/Qwen2.5-7B-Instruct-GGUF'
DEFAULT_GGUF  = 'qwen2.5-7b-instruct-q4_k_m.gguf'
SERVER_PORT   = 8090

# llama-server binary location (bundled in .app Resources)
SCRIPT_DIR    = Path(__file__).resolve().parent
LLAMA_SERVER  = SCRIPT_DIR / 'llama-server'


# ─── Config ───────────────────────────────────────────────
def load_config():
    if CONFIG_FILE.exists():
        with open(CONFIG_FILE) as f:
            return json.load(f)
    return {}


def save_config(cfg):
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(CONFIG_FILE, 'w') as f:
        json.dump(cfg, f, indent=2)


# ─── Download (zero external dependencies) ─────────────────
HF_API_BASE = "https://huggingface.co/api"

def _hf_list_files(model_name: str) -> list:
    """List all files in a HuggingFace repo using the REST API. Zero dependencies."""
    url = f"{HF_API_BASE}/models/{model_name}?blobs=true"
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.loads(resp.read().decode())
    siblings = data.get('siblings', [])
    return [{'path': s['rfilename'], 'size': s.get('size', 0)} for s in siblings]


def _hf_download_url(model_name: str, filename: str) -> str:
    """Construct HuggingFace CDN download URL."""
    return f"https://huggingface.co/{model_name}/resolve/main/{filename}"


def download_model(model_name: str):
    """Download a GGUF model from HuggingFace with progress reporting via stdout JSON."""
    global MODELS_DIR
    cfg = load_config()
    cfg['model_name'] = model_name
    
    # Use configured dir if available
    if cfg.get('model_dir'):
        MODELS_DIR = Path(cfg['model_dir'])
    
    save_config(cfg)
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    output_line({"type": "download", "status": "starting", "model": model_name})

    # Find the right GGUF file via HuggingFace REST API
    output_line({"type": "download", "status": "scanning", "model": model_name})
    try:
        file_infos = _hf_list_files(model_name)
        gguf_files = [f['path'] for f in file_infos if f['path'].endswith('.gguf')]
        
        if not gguf_files:
            output_line({"type": "download", "status": "error", "message": f"No GGUF files found in {model_name}"})
            return False

        # Prefer single-file GGUF, then by quant quality (case-insensitive)
        # Order: Q4_K_M > Q5_K_M > Q4_0 > Q3_K_M > Q2_K > Q6_K > Q8_0 > FP16
        QUANT_ORDER = ['q4_k_m', 'q5_k_m', 'q4_0', 'q3_k_m', 'q2_k', 'q6_k', 'q8_0', 'fp16']
        
        def _gguf_score(fpath):
            """Lower score = better. Single-file preferred over split (-of- pattern)."""
            fname = fpath.lower()
            is_split = '-of-' in fname
            score = 0 if not is_split else 100
            for i, q in enumerate(QUANT_ORDER):
                if q in fname:
                    score += i
                    break
            else:
                score += 99
            return score
        
        gguf_file = min(gguf_files, key=_gguf_score)
        
        # Check if this is part of a split archive
        is_split = '-of-' in gguf_file.lower()
        if is_split:
            base_pattern = re.sub(r'-\d+-of-\d+', '', gguf_file)
            base_escaped = re.escape(base_pattern)
            split_pattern = re.compile(base_escaped + r'-(\d+)-of-(\d+)\.gguf$')
            split_parts = sorted(
                [f for f in gguf_files if split_pattern.match(f)],
                key=lambda f: int(split_pattern.match(f).group(1))
            )
            if len(split_parts) > 1:
                output_line({"type": "download", "status": "info", 
                             "message": f"Split model detected ({len(split_parts)} parts). Downloading all parts."})
                all_ok = True
                for part_file in split_parts:
                    ok = _download_single_file(part_file, model_name)
                    if not ok:
                        all_ok = False
                return all_ok
            else:
                gguf_file = split_parts[0] if split_parts else gguf_file
    except Exception as e:
        output_line({"type": "download", "status": "error", "message": f"Cannot list repo: {e}"})
        return False

    # Single-file download: update config with first/only file
    cfg['model_file'] = Path(gguf_file).name
    cfg['gguf_path'] = str(MODELS_DIR / Path(gguf_file).name)
    cfg['model_dir'] = str(MODELS_DIR)
    save_config(cfg)
    
    return _download_single_file(gguf_file, model_name)


def _download_single_file(gguf_file: str, model_name: str):
    """Download a single GGUF file from HuggingFace. Returns True on success."""
    
    filename = Path(gguf_file).name
    target = MODELS_DIR / filename

    if target.exists():
        size_mb = target.stat().st_size / (1024*1024)
        output_line({"type": "download", "status": "cached", "file": filename, "size_mb": round(size_mb, 1)})
        return True

    # Get file size from HF API, then download with progress
    try:
        # Get file size from repo info
        file_infos = _hf_list_files(model_name)
        size_bytes = next((f['size'] for f in file_infos if f['path'] == gguf_file), 0)
        
        if size_bytes > 0:
            output_line({"type": "download", "status": "downloading", "file": filename, "size_bytes": size_bytes})
        else:
            output_line({"type": "download", "status": "downloading", "file": filename})
        
        url = _hf_download_url(model_name, gguf_file)
        target.parent.mkdir(parents=True, exist_ok=True)
        downloaded = 0
        
        def progress_callback(block_count, block_size, total_size):
            nonlocal downloaded
            downloaded = block_count * block_size
            if total_size > 0:
                pct = min(downloaded / total_size * 100, 99.9)
                output_line({
                    "type": "download", "status": "progress",
                    "downloaded_bytes": downloaded,
                    "total_bytes": total_size,
                    "percent": round(pct, 1)
                })
        
        urllib.request.urlretrieve(url, str(target), reporthook=progress_callback)
        
        size_mb = target.stat().st_size / (1024*1024)
        output_line({"type": "download", "status": "complete", "file": filename, "size_mb": round(size_mb, 1)})
        return True
    except Exception as e:
        output_line({"type": "download", "status": "error", "message": str(e)})
        return False


# ─── Server Lifecycle ─────────────────────────────────────
_server_process = None


def start_server():
    """Start llama-server in the background."""
    global _server_process
    cfg = load_config()

    gguf_path = cfg.get('gguf_path', '')
    if not gguf_path or not Path(gguf_path).exists():
        output_line({"type": "server", "status": "error", "message": "Model file not found. Download first."})
        return False

    port = cfg.get('port', SERVER_PORT)

    # Kill any existing process on this port
    _kill_port(port)

    if not LLAMA_SERVER.exists():
        output_line({"type": "server", "status": "error", "message": f"llama-server not found at {LLAMA_SERVER}"})
        return False

    cmd = [
        str(LLAMA_SERVER),
        '-m', gguf_path,
        '--port', str(port),
        '--host', '127.0.0.1',
        '--ctx-size', '4096',
        '-ngl', '99',  # offload all layers to GPU
    ]

    output_line({"type": "server", "status": "starting", "port": port, "model": Path(gguf_path).name})

    try:
        _server_process = subprocess.Popen(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
        )
    except Exception as e:
        output_line({"type": "server", "status": "error", "message": str(e)})
        return False

    cfg['running'] = True
    cfg['port'] = port
    cfg['pid'] = _server_process.pid
    save_config(cfg)

    # Wait for server to be ready
    output_line({"type": "server", "status": "warming_up"})
    for i in range(30):
        time.sleep(2)
        if _check_health(port):
            output_line({"type": "server", "status": "ready", "port": port, "model": Path(gguf_path).name})
            return True
        if _server_process.poll() is not None:
            output_line({"type": "server", "status": "crashed", "message": "Server process exited unexpectedly"})
            return False
        output_line({"type": "server", "status": "warming_up", "elapsed": (i+1)*2})

    output_line({"type": "server", "status": "timeout", "message": "Server did not become ready within 60s"})
    return False


def stop_server():
    """Stop the running llama-server."""
    global _server_process
    cfg = load_config()
    port = cfg.get('port', SERVER_PORT)
    pid = cfg.get('pid', None)

    # Try to kill by PID
    if pid:
        try:
            os.kill(pid, signal.SIGTERM)
            time.sleep(1)
            try:
                os.kill(pid, 0)  # still alive?
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass
        except OSError:
            pass

    # Also kill anything on the port
    _kill_port(port)

    if _server_process:
        try:
            _server_process.terminate()
            _server_process.wait(timeout=5)
        except:
            try:
                _server_process.kill()
            except:
                pass
        _server_process = None

    cfg['running'] = False
    cfg['pid'] = None
    save_config(cfg)
    output_line({"type": "server", "status": "stopped"})


def check_status():
    """Report current server status."""
    cfg = load_config()
    port = cfg.get('port', SERVER_PORT)
    running = cfg.get('running', False)
    model_file = cfg.get('model_file', '')
    gguf_path = cfg.get('gguf_path', '')
    
    # Check if model file exists
    model_exists = bool(gguf_path) and Path(gguf_path).exists()
    size_mb = 0
    if model_exists:
        size_mb = Path(gguf_path).stat().st_size / (1024*1024)

    # Verify server is actually responding
    healthy = _check_health(port) if running else False

    output_line({
        "type": "status",
        "running": running,
        "healthy": healthy,
        "port": port,
        "model_name": cfg.get('model_name', ''),
        "model_file": model_file,
        "model_exists": model_exists,
        "model_size_mb": round(size_mb, 1),
        "server_available": LLAMA_SERVER.exists(),
    })


# ─── Helpers ──────────────────────────────────────────────
def _check_health(port: int) -> bool:
    """Check if llama-server is responding to health requests."""
    import urllib.request
    try:
        req = urllib.request.Request(f'http://127.0.0.1:{port}/health', method='GET')
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status == 200
    except:
        return False


def _kill_port(port: int):
    """Kill any process listening on the given port."""
    try:
        result = subprocess.run(['lsof', '-ti', f':{port}'], capture_output=True, text=True, timeout=5)
        pids = result.stdout.strip().split()
        for p in pids:
            try:
                os.kill(int(p), signal.SIGTERM)
            except:
                pass
        if pids:
            time.sleep(1)
            for p in pids:
                try:
                    os.kill(int(p), signal.SIGKILL)
                except:
                    pass
    except:
        pass


def output_line(data: dict):
    """Write a JSON line to stdout for Swift to parse."""
    sys.stdout.write(json.dumps(data) + '\n')
    sys.stdout.flush()


# ─── Chat API (used by pet-auto-reply.py) ─────────────────
def chat_completion(model: str, messages: list, temperature: float = 0.7):
    """Send a chat completion request to the local llama-server (OpenAI-compatible API)."""
    import urllib.request, urllib.error
    cfg = load_config()
    port = cfg.get('port', SERVER_PORT)

    url = f'http://127.0.0.1:{port}/v1/chat/completions'
    payload = {
        "model": model or "gpt-3.5-turbo",  # llama-server ignores model name
        "messages": messages,
        "temperature": temperature,
        "max_tokens": 1024,
        "stream": False,
    }
    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})
    
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            result = json.loads(resp.read())
            return result['choices'][0]['message']['content']
    except urllib.error.URLError as e:
        return f"[ERROR] Local LLM not reachable: {e}"
    except Exception as e:
        return f"[ERROR] {e}"


# ─── CLI ──────────────────────────────────────────────────
if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='Local LLM server manager for Desktop Duck')
    parser.add_argument('--download', type=str, help='Download model from HuggingFace (e.g. Qwen/Qwen2.5-7B-Instruct-GGUF)')
    parser.add_argument('--dir', type=str, help='Directory to store downloaded models')
    parser.add_argument('--start', action='store_true', help='Start llama-server')
    parser.add_argument('--stop', action='store_true', help='Stop llama-server')
    parser.add_argument('--status', action='store_true', help='Check server status')

    args = parser.parse_args()

    if args.dir:
        MODELS_DIR = Path(args.dir)

    if args.download:
        download_model(args.download)
    elif args.start:
        start_server()
    elif args.stop:
        stop_server()
    elif args.status:
        check_status()
    else:
        parser.print_help()
