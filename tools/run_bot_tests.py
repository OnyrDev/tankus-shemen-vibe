"""Verify bots offline and through two actual ENet peers."""
import argparse
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--regression", action="store_true")
    args = parser.parse_args()
    output = args.output_dir or Path(tempfile.mkdtemp(prefix="tankus-bots-"))
    output.mkdir(parents=True, exist_ok=True)
    project = Path(__file__).resolve().parents[1]
    base = [args.godot, "--headless", "--path", str(project)]
    failed = False
    processes = []
    try:
        for role in ["server", "client"]:
            extra = ["--", "--bots-client"] if role == "client" else []
            with (output / f"{role}.log").open("w") as log:
                process = subprocess.Popen(base + ["--log-file", str(output / f"{role}-engine.log"),
                    "res://tests/test_bots_network.tscn"] + extra,
                    stdout=log, stderr=subprocess.STDOUT, cwd=project)
            processes.append(process)
        for role, process in zip(["server", "client"], processes):
            code = process.wait(timeout=40)
            log = (output / f"{role}.log").read_text()
            success = code == 0 and "SCRIPT ERROR" not in log and "0 failures" in log
            failed = failed or not success
            print(f"bots network {role}: {'PASS' if success else 'FAIL'}", flush=True)
            if not success:
                print(log[-4500:], flush=True)
        tests = ["test_bots"]
        if args.regression:
            tests += ["test_network", "test_lan_menu", "test_map_rotation", "test_prediction_unit"]
        for test in tests:
            with (output / f"{test}.log").open("w") as log:
                result = subprocess.run(base + ["--fixed-fps", "60", "--quit-after", "12000" if test == "test_bots" else "2000",
                    "--log-file", str(output / f"{test}-engine.log"), f"res://tests/{test}.tscn"],
                    stdout=log, stderr=subprocess.STDOUT, cwd=project, timeout=40)
            text = (output / f"{test}.log").read_text()
            success = result.returncode == 0 and "SCRIPT ERROR" not in text and "[FAIL]" not in text
            if test == "test_bots":
                success = success and "BOTS: 0 failures" in text
            failed = failed or not success
            print(f"{test}: {'PASS' if success else 'FAIL'}", flush=True)
            if not success:
                print(text[-3500:], flush=True)
        print(f"Logs: {output}", flush=True)
        return int(failed)
    finally:
        for process in processes:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)


if __name__ == "__main__":
    raise SystemExit(main())
