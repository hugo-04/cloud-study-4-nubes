export JV_DIR=/tmp/oci-spring JVQ_DIR=/tmp/oci-quarkus JAVA_TOOL_OPTIONS=
SCR=/tmp/claude-0/-home-claude/91a1f301-d8cc-52b1-b5f2-6ef32b63def7/scratchpad
jc() { for m in "" "--quarkus"; do python3 $SCR/javacheck.py $m "$1" 2>&1 | tail -${2:-12}; done; }
