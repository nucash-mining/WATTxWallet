package app.wattxchange.wattx_wallet

import android.content.Context
import android.util.Log
import java.io.File
import java.security.SecureRandom
import java.util.concurrent.LinkedBlockingDeque
import java.util.concurrent.TimeUnit

/**
 * Runs the bundled WATTx daemon on the device.
 *
 * The wallet keeps its own BIP39 seed in the Android Keystore and does not put
 * keys in this node -- the node supplies blocks and the address index, nothing
 * more. That keeps the existing self-custody story intact while the chain is
 * validated on the phone instead of trusted from a public endpoint.
 *
 * The whole WATTx chain is tens of megabytes, so unlike Bitcoin this is a
 * realistic thing to do on a handset: no pruning, full validation.
 */
object FullNode {

    private const val TAG = "wattx-node"

    /** How long to watch a freshly started daemon before calling it up. */
    private const val STARTUP_GRACE_MS = 2500L

    /** Lines of daemon output kept so a startup failure can explain itself. */
    private const val LOG_TAIL = 40

    /** Loopback only. The node must never be reachable from the network. */
    const val RPC_PORT = 13891
    const val P2P_PORT = 1337

    @Volatile
    private var process: Process? = null

    @Volatile
    private var rpcPassword: String? = null

    val isRunning: Boolean get() = process?.isAlive == true

    /**
     * Android only extracts and grants execute permission to files matching
     * lib*.so, so the daemon ships named like a library.
     */
    fun daemon(context: Context): File? =
        File(context.applicationInfo.nativeLibraryDir, "libwattxd.so")
            .takeIf { it.exists() }

    fun supported(context: Context): Boolean = daemon(context)?.canExecute() == true

    fun dataDir(context: Context): File =
        File(context.filesDir, "wattx-node").apply { mkdirs() }

    fun credentials(): Pair<String, String>? =
        rpcPassword?.let { "wattx" to it }

    /**
     * Start the daemon if it is not already up.
     *
     * Returns null on success, or a message to show. Failure is reported rather
     * than thrown: a phone that cannot run a node should fall back to the
     * public endpoint, not crash.
     */
    @Synchronized
    fun start(context: Context): String? {
        if (isRunning) return null
        val bin = daemon(context) ?: return "This build has no bundled node for your device."
        if (!bin.canExecute()) return "The bundled node is not executable on this device."

        val dir = dataDir(context)
        writeConfig(dir)

        return try {
            val tail = LinkedBlockingDeque<String>()
            process = ProcessBuilder(
                listOf(
                    bin.absolutePath,
                    "-datadir=${dir.absolutePath}",
                    "-printtoconsole",
                ) + bootstrapArgs()
            ).redirectErrorStream(true).start().also { p ->
                Thread({
                    runCatching {
                        p.inputStream.bufferedReader().forEachLine { line ->
                            Log.i(TAG, line)
                            while (tail.size >= LOG_TAIL) tail.pollFirst()
                            tail.addLast(line)
                        }
                    }
                }, "wattxd-log").apply { isDaemon = true }.start()
            }

            // ProcessBuilder.start() only means the binary was exec'd. A node
            // that exits a moment later -- datadir locked, no space, corrupt
            // index -- would otherwise look identical to one that is running,
            // and every status afterwards would be a lie.
            val p = process
            if (p != null && p.waitFor(STARTUP_GRACE_MS, TimeUnit.MILLISECONDS)) {
                val why = tail.toList().lastOrNull { it.contains("Error", true) }
                    ?: tail.toList().lastOrNull().orEmpty()
                val code = runCatching { p.exitValue() }.getOrNull()
                process = null
                Log.e(TAG, "node exited during startup (code=$code): $why")
                "The node stopped right after starting" +
                    (if (why.isNotBlank()) ": $why" else " (exit code $code).")
            } else {
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "could not start the node", e)
            "The node could not be started: ${e.message}"
        }
    }

    @Synchronized
    fun stop() {
        process?.let { p ->
            // destroy() sends SIGTERM, which the daemon handles as a clean
            // shutdown; killing it outright can leave the block index corrupt
            // and force a reindex on next start.
            runCatching { p.destroy() }
            runCatching { p.waitFor(20, TimeUnit.SECONDS) }
        }
        process = null
    }

    /**
     * Addresses to bootstrap from, in addition to the DNS seeds.
     *
     * All three of the chain's DNS seeds (seed1/2/3.wattxchange.app) resolve to
     * the SAME single host, so a fresh node effectively gets one bootstrap
     * address and inherits that host's view of the network. Worse, most peers
     * this chain knows about are behind NAT: of the IPv4 addresses in a live
     * node's address manager, only one accepted an inbound connection when
     * this list was built. A phone that relies on DNS alone therefore ends up
     * with one or two peers, or none if that host is down.
     *
     * seednode= is used rather than addnode=: these are queried for addresses
     * and then dropped, so the node still chooses its own peers and this does
     * not pin the wallet to a fixed set. addnode= is used only for the two
     * that are reliably reachable, to guarantee at least one connection.
     */
    private fun bootstrapPeers(): String =
        bootstrapArgs().joinToString("\n") { it.removePrefix("-") } + "\n"

    /**
     * The same peers as command-line arguments. writeConfig() only writes the
     * config on a node's first start, so peers added in later releases would
     * never reach an existing install; passing them on every start does.
     * Duplicates with the config file are harmless.
     */
    private fun bootstrapArgs(): List<String> {
        // Listening WATTx mainnet nodes, all verified accepting connections at
        // the network tip on 2026-10-14. Being unreachable later is harmless --
        // the node simply moves on.
        val reachable = listOf(
            "85.215.243.87:1337",
            "130.61.126.195:1337",
            "193.122.63.133:1337",
            "129.153.28.159:1337",                              // seed relay
        )
        val seedsOnly = listOf(
            "31.17.186.148:1337",                               // offline 2026-10-14
            "[2600:1702:7860:6090::48]:1337",                   // WATTxchange node (IPv6)
        )
        // addnode= for the reachable ones guarantees connections even when every
        // DNS seed fails to resolve (captive portals, filtered networks).
        return reachable.map { "-addnode=$it" } +
            (reachable + seedsOnly).map { "-seednode=$it" }
    }

    /**
     * The config binds RPC to loopback with a freshly generated password: the
     * node must not be reachable from the network, and a fixed credential in a
     * shipped app is the same as no credential at all.
     *
     * txindex and addressindex are on because the wallet's keys are its own --
     * it asks the node about *its* addresses rather than using a node wallet.
     */
    private fun writeConfig(dir: File) {
        val conf = File(dir, "wattx.conf")
        if (conf.exists()) {
            rpcPassword = runCatching {
                conf.readLines().firstOrNull { it.startsWith("rpcpassword=") }
                    ?.substringAfter("=")
            }.getOrNull()
            return
        }
        val password = ByteArray(24).also { SecureRandom().nextBytes(it) }
            .joinToString("") { "%02x".format(it) }
        rpcPassword = password
        conf.writeText(
            """
            server=1
            listen=1
            rpcbind=127.0.0.1
            rpcallowip=127.0.0.1
            rpcport=$RPC_PORT
            rpcuser=wattx
            rpcpassword=$password
            # The wallet's keys live in the app, not in the node.
            disablewallet=1
            # txindex lets any transaction be fetched by id. addressindex is
            # deliberately NOT set: this daemon does not implement it -- it
            # logs "Ignoring unknown configuration value addressindex" and then
            # answers every address query with "No information available".
            # Address balances come from scantxoutset instead, which walks the
            # UTXO set and needs no extra index.
            txindex=1
            # Try both families. Some mobile networks are IPv6-only behind
            # NAT64 and others give no IPv6 at all, and several of this
            # network's listening nodes exist on one family only.
            onlynet=ipv4
            onlynet=ipv6
            dnsseed=1
            """.trimIndent() + "\n" + bootstrapPeers() + "\n"
        )
        runCatching {
            conf.setReadable(false, false)
            conf.setReadable(true, true)
        }
    }
}
