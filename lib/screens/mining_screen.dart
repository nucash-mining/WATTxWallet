import 'dart:async';
import 'package:flutter/material.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:provider/provider.dart';
import '../providers/wallet_provider.dart';
import '../services/cpu_miner.dart';

class MiningScreen extends StatefulWidget {
  const MiningScreen({super.key});
  @override
  State<MiningScreen> createState() => _MiningScreenState();
}

class _MiningScreenState extends State<MiningScreen> {
  final Battery _battery = Battery();
  CpuMiner? _miner;
  MiningStats _stats = const MiningStats();
  BatteryState _batteryState = BatteryState.unknown;
  int _batteryLevel = 100;
  int _threads = 1;
  bool _warningAcknowledged = false;
  StreamSubscription? _statsSub;
  Timer? _batteryTimer;

  @override
  void initState() {
    super.initState();
    _pollBattery();
    _batteryTimer = Timer.periodic(const Duration(seconds: 10), (_) => _pollBattery());
  }

  Future<void> _pollBattery() async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      if (mounted) setState(() { _batteryLevel = level; _batteryState = state; });
    } catch (_) {}
  }

  Future<void> _startMining() async {
    if (!_warningAcknowledged) {
      final ok = await _showWarningDialog();
      if (!ok) return;
      _warningAcknowledged = true;
    }

    final rpc = context.read<WalletProvider>().rpc;
    _miner = CpuMiner(rpc, threads: _threads);
    _statsSub = _miner!.statsStream.listen((s) {
      if (mounted) setState(() => _stats = s);
    });
    await _miner!.start();
    await WakelockPlus.enable();
    setState(() {});
  }

  void _stopMining() {
    _miner?.stop();
    _miner = null;
    _statsSub?.cancel();
    WakelockPlus.disable();
    setState(() => _stats = const MiningStats());
  }

  Future<bool> _showWarningDialog() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: Row(children: const [
          Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
          SizedBox(width: 10),
          Text('Mining Warning', style: TextStyle(color: Colors.white)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _bullet('CPU mining generates significant heat and drains battery quickly.'),
          _bullet('Mining on battery may reduce its lifespan over time.'),
          _bullet('Performance varies by device — budget phones may lag.'),
          _bullet('This is for testnet only. Real WATTx mining uses GPU/ASIC.'),
          if (_batteryState != BatteryState.charging)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red.withOpacity(0.4)),
                ),
                child: Row(children: [
                  const Icon(Icons.battery_alert, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Battery at $_batteryLevel% and NOT charging!\nPlug in before mining.',
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ]),
              ),
            ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _batteryState != BatteryState.charging && _batteryLevel < 20
                  ? Colors.red : const Color(0xFFF7C948),
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('I Understand — Mine'),
          ),
        ],
      ),
    ) ?? false;
  }

  Widget _bullet(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('• ', style: TextStyle(color: Color(0xFFF7C948))),
      Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13))),
    ]),
  );

  @override
  void dispose() {
    _stopMining();
    _batteryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = _miner?.state == MinerState.running;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('CPU Mining', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Battery status strip
        _BatteryStrip(level: _batteryLevel, state: _batteryState),
        const SizedBox(height: 16),

        // Miner status card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isRunning ? const Color(0xFF3FB950) : Colors.white12,
            ),
          ),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  isRunning ? 'Mining Active' : 'Miner Stopped',
                  style: TextStyle(
                    color: isRunning ? const Color(0xFF3FB950) : Colors.white54,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  isRunning ? 'Testnet SHA-256d' : 'Tap Start to begin',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ]),
              if (isRunning)
                _PulsingDot()
              else
                const Icon(Icons.power_settings_new, color: Colors.white24, size: 32),
            ]),
            if (isRunning) ...[
              const SizedBox(height: 20),
              _StatsGrid(stats: _stats),
            ],
          ]),
        ),

        const SizedBox(height: 16),

        // Thread selector
        if (!isRunning) ...[
          const Text('CPU Threads', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: List.generate(4, (i) {
            final t = i + 1;
            final selected = _threads == t;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _threads = t),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFFF7C948) : const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected ? const Color(0xFFF7C948) : Colors.white12,
                    ),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('$t', style: TextStyle(
                      color: selected ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    )),
                    Text(t == 1 ? 'core' : 'cores', style: TextStyle(
                      color: selected ? Colors.black87 : Colors.white38,
                      fontSize: 9,
                    )),
                  ]),
                ),
              ),
            );
          })),
          const SizedBox(height: 8),
          Text(
            _threads == 1 ? 'Low heat / Low battery drain' :
            _threads == 2 ? 'Moderate heat / Moderate drain' :
            _threads == 3 ? 'High heat / High drain — plugin recommended' :
            'Maximum heat — PLUG IN before using 4 cores',
            style: TextStyle(
              color: _threads >= 3 ? Colors.orange : Colors.white38,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Start/Stop button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: isRunning ? Colors.red.shade700 : const Color(0xFFF7C948),
              foregroundColor: isRunning ? Colors.white : Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: Icon(isRunning ? Icons.stop : Icons.play_arrow),
            label: Text(isRunning ? 'Stop Mining' : 'Start Mining', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            onPressed: isRunning ? _stopMining : _startMining,
          ),
        ),

        const SizedBox(height: 24),
        const _MiningInfoBox(),
      ]),
    );
  }
}

class _BatteryStrip extends StatelessWidget {
  final int level;
  final BatteryState state;
  const _BatteryStrip({required this.level, required this.state});

  @override
  Widget build(BuildContext context) {
    final isCharging = state == BatteryState.charging;
    final color = level < 20 && !isCharging ? Colors.red
        : level < 40 ? Colors.orange
        : const Color(0xFF3FB950);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(
          isCharging ? Icons.battery_charging_full : Icons.battery_std,
          color: color,
          size: 20,
        ),
        const SizedBox(width: 10),
        Text(
          '$level%  ${isCharging ? "Charging" : "On battery"}',
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
        if (!isCharging && level < 40) ...[
          const Spacer(),
          Text(
            level < 20 ? 'LOW — plug in!' : 'Mining not recommended',
            style: TextStyle(color: color, fontSize: 11),
          ),
        ],
      ]),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final MiningStats stats;
  const _StatsGrid({required this.stats});

  String _formatHr(double hr) {
    if (hr > 1e6) return '${(hr / 1e6).toStringAsFixed(2)} MH/s';
    if (hr > 1e3) return '${(hr / 1e3).toStringAsFixed(2)} KH/s';
    return '${hr.toStringAsFixed(1)} H/s';
  }

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 2.4,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        _StatTile('Hash Rate', _formatHr(stats.hashRate), Icons.speed),
        _StatTile('Total Hashes', _fmt(stats.totalHashes), Icons.calculate),
        _StatTile('Blocks Found', '${stats.blocksFound}', Icons.check_circle_outline),
        _StatTile('Elapsed', _fmtDur(stats.elapsed), Icons.timer_outlined),
      ],
    );
  }

  String _fmt(int n) {
    if (n > 1e9) return '${(n / 1e9).toStringAsFixed(2)}B';
    if (n > 1e6) return '${(n / 1e6).toStringAsFixed(2)}M';
    if (n > 1e3) return '${(n / 1e3).toStringAsFixed(1)}K';
    return '$n';
  }

  String _fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _StatTile(this.label, this.value, this.icon);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.05),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(children: [
      Icon(icon, color: const Color(0xFFF7C948), size: 18),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ]),
    ]),
  );
}

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}
class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _anim,
    child: Container(
      width: 14, height: 14,
      decoration: const BoxDecoration(color: Color(0xFF3FB950), shape: BoxShape.circle),
    ),
  );
}

class _MiningInfoBox extends StatelessWidget {
  const _MiningInfoBox();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF161B22),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white12),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('About CPU Mining', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13)),
      const SizedBox(height: 8),
      _line('Only active during WATTx testnet PoW phase (blocks 0–1000).'),
      _line('After block 1000, the chain switches to Proof-of-Stake.'),
      _line('For staking, use the Staking screen and unlock your wallet.'),
      _line('Real-world WATTx mining uses merged mining via GPU.'),
    ]),
  );

  Widget _line(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('• ', style: TextStyle(color: Color(0xFFF7C948))),
      Expanded(child: Text(t, style: const TextStyle(color: Colors.white38, fontSize: 12))),
    ]),
  );
}
