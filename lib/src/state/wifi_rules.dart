/// Wi-Fi 联动里最容易出错的那部分判定，单独抽成纯函数方便单测。
enum WifiAutoLoginDecision {
  /// 当前不在目标 Wi-Fi，什么都不做。
  notOnTarget,

  /// 已经在这个 Wi-Fi 上处理过了（同一次连接不重复触发）。
  alreadyHandled,

  /// 账号没开「发现该 Wi-Fi 时自动登录」。
  disabled,

  /// 已有会话 / 正在连接：沿用现有票据，绝不重复 login。
  keepSession,

  /// 可以登录。
  login,
}

/// 判断「刚连上目标 Wi-Fi」时该不该自动登录。
///
/// 关键约束：**一个 Wi-Fi 连接周期只触发一次**，而且当前已有会话时一律不登录。
/// 重复 `esf_login` 会先 term 掉服务端会话再重新取票，票据被作废后
/// 保活会连环失败，所以断网重连的恢复交给核心保活线程自己退避重试。
WifiAutoLoginDecision decideWifiAutoLogin({
  required String target,
  required String current,
  required String previous,
  required String alreadyHandled,
  required bool autoLoginEnabled,
  required bool hasSession,
  required bool busy,
}) {
  final wanted = target.trim();
  if (wanted.isEmpty || current != wanted) return WifiAutoLoginDecision.notOnTarget;
  if (previous == wanted || alreadyHandled == wanted) {
    return WifiAutoLoginDecision.alreadyHandled;
  }
  if (!autoLoginEnabled) return WifiAutoLoginDecision.disabled;
  if (hasSession || busy) return WifiAutoLoginDecision.keepSession;
  return WifiAutoLoginDecision.login;
}
