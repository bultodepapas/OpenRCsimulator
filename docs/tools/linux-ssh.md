# Linux SSH connection

The Windows development account has an `openrc-linux` SSH alias for the existing
`vscode-megatron` Linux route. Connection settings and credentials stay in the
account's `.ssh` directory, outside Git. The original VS Code alias is preserved.

```powershell
ssh -G openrc-linux
ssh -T openrc-linux 'id -un; hostname; uname -sm; python3 --version'
ssh openrc-linux
```

The alias reuses the existing identity and dedicated known-host entry. It requires
the pinned host key, disables agent forwarding and automatic host-key updates, and
uses batch authentication with a 15-second connection timeout. Keep host-key
verification enabled; do not rotate/copy keys or accept a changed fingerprint to
work around a connection failure. See the [OpenSSH configuration contract](https://man.openbsd.org/ssh_config).

On another client, provision its own authorized identity and verified host key;
this account's alias is not repository-wide SSH configuration. Preserve the remote
`~/OpenRCsimulator` checkout, VS Code workspace and frozen research campaigns.
Confirm current paths and free space after connecting before preparing a new job.

## Readiness and orchestration

SSH configuration is separate from host availability and worker qualification.
Use the local Tailscale client's status for the configured peer and a bounded SSH
connection check. Do not scan the network or substitute another machine silently.
An offline peer needs to be brought online, or the operator must supply its new
route and identity.

The local connection check receipt is
`C:\ProgramData\OpenRC\testqueue\connections\linux-ssh.json` by default (under
`OPENRC_TESTQUEUE_ROOT` when set). It records a connection check at `checked_at`;
the shell commands above do not automatically refresh it. It is not coordinator
enrollment or evidence of a qualified adapter. It contains no private key or password.
Recheck connectivity before relying on an old receipt.

Persistent Linux worker transport, process containment, isolated imports and host
resource budgets remain gated by [TQ-02](../plans/agent-test-orchestrator.md).
Do not dispatch simulator jobs merely because SSH succeeds. The
[test-queue operating guide](../../tools/testqueue/README.md) owns job admission.
