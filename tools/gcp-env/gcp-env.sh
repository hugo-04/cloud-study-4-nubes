export JV_DIR=/tmp/gcp-spring JVQ_DIR=/tmp/gcp-quarkus
SCR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
jc() { for m in "" "--quarkus"; do python3 $SCR/javacheck.py $m "$1" 2>&1 | tail -${2:-12}; done; }
