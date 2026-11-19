#!/usr/bin/env bash
# DUCKY Tunnel Suite v1.0  |  Channel: t.me/Em4dloverS  |  Support: t.me/KaMr4ng
MODDIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/modules"
for m in nucleus kernel_gre reverse_pro preflight sentinel cli_ui; do . "$MODDIR/$m.sh"; done

case "${1:-}" in
  api)
    shift; need_root
    case "${1:-}" in
      catalog) echo "$CATALOG" ;;
      list) list_nodes ;;
      status) status_matrix machine ;;
      rank) rank_nodes machine ;;
      ip) myip; echo "$MYIP" ;;
      ip6) myip6; echo "${MYIP6:-}" ;;
      sysinfo) sys_telemetry_json ;;
      act) node_act "$2" "$3" ;;
      bulk) bulk_act "$2" ;;
      clone) clone_node "$2" "$3" "${4:-}" ;;
      hop) hop_cport "$2" "${3:-}" ;;
      failover) manual_failover "$2" ;;
      edit) shift; edit_node "$@" ;;
      tune) auto_tune_server "${2:-throughput}" ;;
      rps) tune_rps ;;
      shield) fw_shield "${2:-enable}" ;;
      swap) make_swap "${2:-2048}" ;;
      ntp) sync_ntp "${2:-Asia/Tehran}" ;;
      clean) clean_orphans ;;
      mtu) mtu_probe "$2" "${3:-apply}" ;;
      trace) run_trace "$2" ;;
      sockets) node_sockets "$2" ;;
      rawconf) show_raw_conf "$2" ;;
      test-server) conntest_server ;;
      test-run) conntest_client "$2" ;;
      dns) set_dns "${2:-shecan}" ;;
      sentinel) sentinel_ctl "${2:-status}" "${3:-40}" ;;
      tgbot) tgbot_ctl "${2:-status}" ;;
      backup) backup_vault "${2:-}" ;;
      restore) restore_vault "$2" ;;
      doctor) run_doctor machine ;;
      link) make_link "$2" ;;
      links) export_all_links ;;
      apply-link) _o=$(apply_link "$2"); aq_log done "$_o"; echo "$_o" ;;
      apply-batch) apply_batch_links "$2" ;;
      deploy)
        NAME=$2 TYPE=$3 ROLE=$4 LOCAL=$5 REMOTE=$6 PORTS=$7 CPORT=$8 TOKEN=$9 IDX=${10} PEER=${11:-} NOTE=${12:-} TMTU=${13:-} BACKUP_NODE=${14:-} QUOTA_GB=${15:-0} EDGE_IP=${16:-} POOL=${17:-}
        _o=$(deploy_node); aq_log done "$_o"; echo "$_o"
        ;;
    esac
    exit 0
    ;;
  link) shift; need_root; make_link "$1"; exit 0 ;;
  links) need_root; export_all_links; exit 0 ;;
  apply-link) shift; need_root; apply_link "$1"; exit 0 ;;
  status) need_root; detect_os; status_matrix; exit 0 ;;
  rank) need_root; detect_os; rank_nodes; exit 0 ;;
  top) need_root; detect_os; live_monitor; exit 0 ;;
  test) shift; need_root; [ -n "${1:-}" ] && conntest_client "$1" || conntest_server; exit 0 ;;
  doctor) need_root; detect_os; run_doctor; exit 0 ;;
  sentinel-run) need_root; sentinel_loop "${2:-40}"; exit 0 ;;
  backup) shift; need_root; backup_vault "${1:-}"; exit 0 ;;
  restore) shift; need_root; restore_vault "$1"; exit 0 ;;
  update) need_root; self_update; exit 0 ;;
  version|-v|--version) echo "DUCKY Tunnel Suite v$VER"; exit 0 ;;
esac

need_root; detect_os
mkdir -p "$MESH" "$EXEC" "$SPEC" "$CIPHER" "$SNAP" "$JOBS" "$ROOT/etc/sysctl.d" 2>/dev/null
main_menu
