export JV_DIR=/tmp/tr-spring JVQ_DIR=/tmp/tr-quarkus
SCR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
jc() { for m in "" "--quarkus"; do python3 $SCR/javacheck.py $m "$1" 2>&1 | tail -${2:-12}; done; }
