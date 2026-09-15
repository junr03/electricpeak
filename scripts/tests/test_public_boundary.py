import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).parents[1] / "check-public-boundary.py"
SPEC = importlib.util.spec_from_file_location("check_public_boundary", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class PublicBoundaryTests(unittest.TestCase):
    def commit(self, root: Path, files: dict[str, str]) -> str:
        for name, content in files.items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        subprocess.run(["git", "-C", str(root), "add", "--all"], check=True)
        subprocess.run(
            [
                "git",
                "-C",
                str(root),
                "-c",
                "user.name=Test",
                "-c",
                "user.email=test@example.invalid",
                "-c",
                "commit.gpgsign=false",
                "commit",
                "--quiet",
                "-m",
                "test",
            ],
            check=True,
        )
        return (
            subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"])
            .decode()
            .strip()
        )

    def inspect(self, files: dict[str, str]) -> list[str]:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            subprocess.run(["git", "init", "--quiet", str(root)], check=True)
            revision = self.commit(root, files)
            previous = Path.cwd()
            try:
                import os

                os.chdir(root)
                return MODULE.inspect_revision(revision)
            finally:
                os.chdir(previous)

    def test_sanitized_examples_pass(self):
        self.assertEqual(
            self.inspect(
                {
                    "deployment.nix.example": 'domain = "example.invalid";\n',
                    "README.md": "Use 192.0.2.10 in examples.\n",
                }
            ),
            [],
        )

    def test_private_configuration_path_is_rejected(self):
        failures = self.inspect({"private-config/configuration.nix": "{}\n"})
        self.assertTrue(any("belongs in electricpeak-sensitive" in failure for failure in failures))

    def test_production_identity_and_topology_are_rejected(self):
        private_address = ".".join(("192", "168", "68", "94"))
        production_domain = ".".join(("homeassistant", "electricpeak", "net"))
        filesystem_uuid = "-".join(
            ("2b3d9251", "c5a8", "4617", "8f3d", "4db03f4a2dcc")
        )
        device_id = "".join(("d5161bd8468b483c", "6e697cef4e1ed5e4"))
        failures = self.inspect(
            {
                "configuration.nix": (
                    f'host = "{production_domain}";\n'
                    f'address = "{private_address}";\n'
                    f'device = "/dev/disk/by-uuid/{filesystem_uuid}";\n'
                ),
                "automations.yaml": f"device_id: {device_id}\n",
            }
        )
        self.assertGreaterEqual(len(failures), 4)

    def test_private_key_is_rejected(self):
        private_key_header = " ".join(("-----BEGIN", "OPENSSH", "PRIVATE", "KEY-----"))
        failures = self.inspect(
            {"notes.txt": f"{private_key_header}\nnot-a-real-key\n"}
        )
        self.assertTrue(any("private key material" in failure for failure in failures))


if __name__ == "__main__":
    unittest.main()
