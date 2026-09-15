import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).parents[2] / ".github/scripts/deploy-public-source.sh"


class DeploymentTests(unittest.TestCase):
    def run_controller(self, *, fail_build=False, bad_revision=False, activate=False):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            binaries, source, controller = root / "bin", root / "source", root / "controller"
            binaries.mkdir()
            (source / "private-config").mkdir(parents=True)
            (source / "private-config/configuration.nix").write_text("{}")
            (controller / ".github/scripts").mkdir(parents=True)
            for name in ["nixos-rebuild-deploy.sh", "verify-deployment-runtime.sh"]:
                (controller / ".github/scripts" / name).write_text("# mock")
            mock = f'''#!{sys.executable}
import os, sys
from pathlib import Path
root = Path(os.environ["MOCK_ROOT"])
cmd = sys.argv[-1]
with (root / "calls").open("a") as out: out.write(cmd + "\\n")
if Path(sys.argv[0]).name == "rsync": sys.exit(0)
if "nixos-rebuild build" in cmd and os.environ["FAIL_BUILD"] == "1": sys.exit(1)
if "mktemp -d" in cmd: print("/tmp/electricpeak-deploy.test123")
elif cmd.startswith("systemd-run"): (root / "activated").touch()
elif "systemctl --user show" in cmd: print("ActiveState=inactive\\nExecMainStatus=0")
elif "docker ps" in cmd: print("unchanged-container-id")
elif "readlink -f" in cmd:
    print("/nix/store/" + ("candidate" if "/result" in cmd or (root / "activated").exists() else "current") + "-nixos-system-test")
elif ".active-system" in cmd: print("/nix/store/candidate-nixos-system-test")
'''
            for tool in ["ssh", "rsync"]:
                path = binaries / tool
                path.write_text(mock)
                path.chmod(0o755)
            env = dict(
                os.environ,
                PATH=str(binaries) + os.pathsep + os.environ["PATH"],
                MOCK_ROOT=tmp,
                FAIL_BUILD=str(int(fail_build)),
                ACTIVATE=str(activate).lower(),
                PUBLIC_REVISION="invalid" if bad_revision else "a" * 40,
                PRIVATE_REVISION="b" * 40,
                SERVER_USER="deployer",
                TS_SERVER_HOST="server.example.invalid",
                DEPLOYMENT_UNIT="electricpeak-deploy-123-1",
            )
            result = subprocess.run(
                ["bash", str(SCRIPT), str(source), str(controller)],
                env=env,
                capture_output=True,
                text=True,
            )
            calls = (root / "calls").read_text() if (root / "calls").exists() else ""
            return result, calls

    def test_default_handoff_builds_without_starting_activation(self):
        result, calls = self.run_controller()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("nixos-rebuild build", calls)
        self.assertIn("test -L '/tmp/electricpeak-deploy.test123/source/result' && rm", calls)
        self.assertNotIn("systemd-run", calls)
        self.assertIn("container IDs are unchanged", result.stdout)

    def test_failed_build_never_activates(self):
        result, calls = self.run_controller(fail_build=True, activate=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("systemd-run", calls)

    def test_invalid_revision_never_connects(self):
        result, calls = self.run_controller(bad_revision=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, "")

    def test_explicit_activation_checks_exact_built_generation_and_runtime(self):
        result, calls = self.run_controller(activate=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("systemd-run --user --no-block", calls)
        self.assertLess(
            calls.index("test -L '/tmp/electricpeak-deploy.test123/source/result'"),
            calls.index("systemd-run --user"),
        )
        self.assertIn(".active-system", calls)
        self.assertIn("verify-deployment-runtime.sh", calls)


if __name__ == "__main__":
    unittest.main()
