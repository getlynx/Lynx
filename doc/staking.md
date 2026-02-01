# Staking and Wallet Security

Lynx utilizes a Proof-of-Stake (PoS) consensus mechanism which requires users to keep their wallets online and unlocked to participate in securing the network and earning rewards.

## Staking Requirements

To stake your coins and earn rewards, your wallet must be:
1.  **Online**: The node must be running and connected to peers.
2.  **Encrypted & Unlocked**: If your wallet is encrypted (recommended), it must be unlocked to sign new blocks.

## Staking Only Mode

Unlocking your wallet fully exposes your private keys in memory, which allows for any transaction to be sent. For users running a staking node on a remote server or a less secure environment, this presents a security risk.

To mitigate this, Lynx supports a **Staking Only** mode. When unlocked in this mode, the wallet is capable of signing new blocks (staking) but **cannot** send funds or export private keys.

### Usage

To unlock your wallet for staking only, use the `walletpassphrase` command with the third argument set to `true`.

**Syntax:**
```bash
lynx-cli walletpassphrase "passphrase" timeout [staking_only]
```

**Arguments:**
1.  `passphrase`: The wallet passphrase.
2.  `timeout`: The time in seconds to keep the wallet unlocked. Set to `0` for no automatic relock (stays unlocked until `walletlock` is called or the node restarts). Positive values are capped at ~3 years.
3.  `staking_only`: (Optional, default=false) Set to `true` to unlock for staking only.

### Example

Unlock the wallet indefinitely for staking only:

```bash
lynx-cli walletpassphrase "mySecretPassphrase" 0 true
```

If you attempt to send funds while the wallet is in this state, you will receive an error:
`Error: Wallet is unlocked for staking only.`

### Verifying Status

You can check if your wallet is currently staking by checking the debug log or using `getwalletinfo` (if available and updated) or simply by observing that your balance remains safe while you are successfully generating blocks.

## Best Practices

-   **Always** encrypt your wallet.
-   Use **Staking Only** mode (`true`) whenever you are purely staking, especially on VPS or always-on devices.
-   Only unlock fully when you explicitly need to send a transaction.
