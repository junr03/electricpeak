"""Exercise deployment failures with fake tools; never contact production."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parents[1]
PRIVATE_MARKER = "do-not-publish.example.test"

# One fake executable serves each tool, selected by its filename. Python keeps
# the failure fixtures and invocation trace portable within unittest.
FAKE_TOOL = r'''
import json
import os
from pathlib import Path
import subprocess
import sys

tool = Path(sys.argv[0]).name
args = sys.argv[1:]
scenario = os.environ.get("SCENARIO", "success")
with open(os.environ["TRACE"], "a") as trace:
    trace.write(json.dumps([tool, *args]) + "\n")
if tool == "timeout":
    sys.exit(subprocess.call(args[1:]))
if tool == "sleep":
    sys.exit(0)
if tool == "tailscale":
    if args[0] == "status":
        if scenario == "status_unavailable":
            sys.exit(1)
        print(json.dumps({
            "BackendState": "NeedsLogin" if scenario == "logged_out" else "Running",
            "Self": {"Online": True, "DNSName": "do-not-publish.example.test"},
            "Health": ["do-not-publish.example.test"],
            "Peer": {} if scenario == "invisible" else {
                "fixture": {"Online": scenario != "offline", "TailscaleIPs": ["192.0.2.17"]}
            },
        }))
    else:
        print("do-not-publish.example.test via private relay")
        sys.exit(1 if scenario == "ping_failed" else 0)
elif tool == "getent":
    if scenario == "dns_failed":
        sys.exit(2)
    print("192.0.2.17 STREAM do-not-publish.example.test")
elif tool == "nc":
    if scenario in ("tcp_timeout", "tcp_refused"):
        print("Connection refused" if scenario == "tcp_refused" else "timed out", file=sys.stderr)
        print("do-not-publish.example.test", file=sys.stderr)
        sys.exit(1)
elif tool == "rsync":
    sys.exit(1 if scenario == "transfer_failed" else 0)
elif tool == "ssh":
    command = args[-1]
    if command == "true":
        failures = {
            "auth_failed": "Permission denied (publickey).",
            "host_key_failed": "Host key verification failed.",
            "handshake_failed": "Connection closed by remote host",
        }
        if scenario in failures:
            print(failures[scenario] + " do-not-publish.example.test", file=sys.stderr)
            sys.exit(255)
        if scenario == "transient":
            counter = Path(os.environ["COUNTER"])
            count = int(counter.read_text()) if counter.exists() else 0
            counter.write_text(str(count + 1))
            if count == 0:
                sys.exit(255)
        sys.exit(0)
    if scenario == "snapshot_failed":
        sys.exit(255)
    if command.startswith("mktemp"):
        print("/tmp/electricpeak-deploy.fixture")
    elif "nixos-rebuild build" in command:
        sys.exit(1 if scenario == "build_failed" else 0)
    elif "systemctl --user show" in command:
        print("ActiveState=inactive")
        print("ExecMainStatus=" + ("1" if scenario == "activation_failed" else "0"))
    elif "verify-deployment-runtime.sh" in command:
        sys.exit(1 if scenario == "runtime_failed" else 0)
    elif command.startswith("readlink") or command.startswith("cat "):
        print("/nix/store/fixture-nixos-system-test")
    elif command.startswith("docker ps"):
        print("fixture-container")
'''


class DeploymentDiagnosticsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        tools = self.root / "bin"
        tools.mkdir()
        for name in ("tailscale", "getent", "nc", "ssh", "timeout", "sleep", "rsync"):
            executable = tools / name
            executable.write_text(f"#!{sys.executable}\n" + FAKE_TOOL)
            executable.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}",
                        HOME=str(self.root), SERVER_USER="deployer",
                        TS_SERVER_HOST=PRIVATE_MARKER,
                        PUBLIC_REVISION="a" * 40, PRIVATE_REVISION="b" * 40,
                        DEPLOYMENT_UNIT="electricpeak-deploy-123-1",
                        TRACE=str(self.root / "trace"), COUNTER=str(self.root / "counter"),
                        GITHUB_STEP_SUMMARY=str(self.root / "summary"))

    def run_script(self, scenario="success", deploy=False, activate=True):
        env = dict(self.env, SCENARIO=scenario, ACTIVATE=str(activate).lower())
        for path in (env["TRACE"], env["COUNTER"], env["GITHUB_STEP_SUMMARY"]):
            Path(path).unlink(missing_ok=True)
        name = "deploy-public-source.sh" if deploy else "check-deployment-connection.sh"
        args = []
        if deploy:
            source = self.root / "source"
            (source / "private-config").mkdir(parents=True)
            (source / "private-config/configuration.nix").write_text("{}")
            controller = self.root / "controller"
            (controller / ".github/scripts").mkdir(parents=True)
            for script in ("nixos-rebuild-deploy.sh", "verify-deployment-runtime.sh"):
                (controller / ".github/scripts" / script).touch()
            args = [str(source), str(controller)]
        result = subprocess.run(["bash", str(SCRIPTS / name), *args], env=env,
                                capture_output=True, text=True, timeout=10)
        summary = Path(env["GITHUB_STEP_SUMMARY"]).read_text()
        self.output = result.stdout + result.stderr + summary
        self.trace = [json.loads(line) for line in Path(env["TRACE"]).read_text().splitlines()]
        return result

    def test_success_hides_private_details_and_does_not_deploy(self):
        self.assertEqual(self.run_script().returncode, 0)
        self.assertIn("Connection preflight passed", self.output)
        self.assertNotIn(PRIVATE_MARKER, self.output)
        self.assertNotIn("192.0.2.17", self.output)
        self.assertEqual([call[-1] for call in self.trace if call[0] == "ssh"], ["true"])

    def test_failure_categories_and_redaction(self):
        cases = {
            "status_unavailable": "status unavailable",
            "logged_out": "not logged in",
            "dns_failed": "name resolution failed",
            "tcp_timeout": "unreachable or timed out",
            "tcp_refused": "connection refused",
            "auth_failed": "SSH authentication failed",
            "host_key_failed": "host identity verification failed",
            "handshake_failed": "SSH handshake or remote command failed",
        }
        for scenario, expected in cases.items():
            with self.subTest(scenario=scenario):
                result = self.run_script(scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(expected, self.output)
                self.assertIn("::error::", self.output)
                self.assertNotIn(PRIVATE_MARKER, self.output)

    def test_optional_tailscale_diagnostics_do_not_block_working_ssh(self):
        for scenario, expected in (("invisible", "not visible"), ("offline", "offline"),
                                   ("ping_failed", "discovery ping: failed")):
            with self.subTest(scenario=scenario):
                self.assertEqual(self.run_script(scenario).returncode, 0)
                self.assertIn(expected, self.output)

    def test_transient_ssh_failure_retries(self):
        self.assertEqual(self.run_script("transient").returncode, 0)
        self.assertIn("attempt 2/3", self.output)
        self.assertNotIn("attempt 3/3", self.output)

    def test_authentication_failure_is_not_retried(self):
        self.assertNotEqual(self.run_script("auth_failed").returncode, 0)
        self.assertEqual(len([call for call in self.trace if call[0] == "ssh"]), 1)

    def test_unreachable_port_never_attempts_authentication(self):
        self.assertNotEqual(self.run_script("tcp_timeout").returncode, 0)
        self.assertEqual(len([call for call in self.trace if call[0] == "nc"]), 3)
        self.assertFalse(any(call[0] == "ssh" for call in self.trace))

    def test_deployment_failure_reports_stage_and_preserves_exit_code(self):
        for scenario, stage, code in (("snapshot_failed", "Read current server state", 255),
                                      ("transfer_failed", "Transfer assembled sources", 1),
                                      ("build_failed", "Production build", 1),
                                      ("activation_failed", "Wait for activation", 1),
                                      ("runtime_failed", "Runtime verification", 1)):
            with self.subTest(scenario=scenario):
                # Each deploy needs fresh source/controller fixture directories.
                with tempfile.TemporaryDirectory(dir=self.root) as case_root:
                    original_root = self.root
                    self.root = Path(case_root)
                    try:
                        result = self.run_script(scenario, deploy=True)
                    finally:
                        self.root = original_root
                self.assertEqual(result.returncode, code)
                self.assertIn(f"Deployment failed during: {stage}", self.output)
                ssh_commands = [call[-1] for call in self.trace if call[0] == "ssh"]
                self.assertFalse(any(command.startswith("rm -rf") for command in ssh_commands))
                if scenario != "snapshot_failed":
                    self.assertIn("Inspect private diagnostics on the server", self.output)

    def test_successful_build_only_handoff_never_activates(self):
        self.assertEqual(self.run_script(deploy=True, activate=False).returncode, 0)
        self.assertIn("Deployment completed successfully", self.output)
        self.assertFalse(any("systemd-run" in call[-1] for call in self.trace if call[0] == "ssh"))

    def test_successful_activation_reports_stages_and_cleans_up(self):
        self.assertEqual(self.run_script(deploy=True).returncode, 0)
        self.assertIn("Deployment stage: Runtime verification", self.output)
        self.assertTrue(any(call[-1].startswith("rm -rf") for call in self.trace if call[0] == "ssh"))


if __name__ == "__main__":
    unittest.main()
