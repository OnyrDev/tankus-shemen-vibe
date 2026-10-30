"""Run real ENet host/client A/B tests with artificial movement latency."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--regression", action="store_true")
    args = parser.parse_args()
    output = args.output_dir or Path(tempfile.mkdtemp(prefix="tankus-prediction-"))
    output.mkdir(parents=True, exist_ok=True)
    project = Path(__file__).resolve().parents[1]
    base = [args.godot, "--headless", "--path", str(project)]
    cases = [(100, True), (100, False), (0, True), (200, True)]
    runs = []
    try:
        for index, (latency, prediction) in enumerate(cases):
            common = ["res://tests/test_prediction.tscn", "--",
                      "--prediction-test-port=" + str(17110 + index)]
            processes = []
            for role in ["server", "client"]:
                path = output / f"{index}-{role}.log"
                options = []
                if role == "client":
                    options = ["--prediction-test-client", f"--movement-latency-ms={latency}"]
                    if not prediction:
                        options.append("--disable-movement-prediction")
                with path.open("w") as log:
                    process = subprocess.Popen(
                        base + ["--log-file", str(output / f"{index}-{role}-engine.log")]
                        + common + options, cwd=project, stdout=log, stderr=subprocess.STDOUT)
                processes.append(process)
            runs.append((index, processes))
        failed = False
        metrics = []
        for index, processes in runs:
            codes = [process.wait(timeout=35) for process in processes]
            client_log = (output / f"{index}-client.log").read_text()
            lines = [line.removeprefix("PREDICTION_METRICS ") for line in client_log.splitlines()
                     if line.startswith("PREDICTION_METRICS ")]
            if lines:
                result = json.loads(lines[-1])
                metrics.append(result)
                print(json.dumps(result), flush=True)
            if any(codes) or not lines:
                failed = True
                print(f"Case {index} failed: exit codes {codes}; logs: {output}", flush=True)
        if args.regression:
            for test in ["test_prediction_unit", "test_network", "test_lan_menu", "test_map_rotation"]:
                path = output / f"{test}.log"
                with path.open("w") as log:
                    result = subprocess.run(base + ["--log-file", str(output / f"{test}-engine.log"),
                        f"res://tests/{test}.tscn"], cwd=project, stdout=log,
                        stderr=subprocess.STDOUT, timeout=30)
                text = path.read_text()
                success = result.returncode == 0 and "SCRIPT ERROR" not in text
                failed = failed or not success
                print(f"{test}: {'PASS' if success else 'FAIL'}", flush=True)
        (output / "metrics.json").write_text(json.dumps(metrics, indent=2) + "\n")
        print(f"Logs and metrics: {output}", flush=True)
        return int(failed)
    finally:
        for _, processes in runs:
            for process in processes:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)


if __name__ == "__main__":
    raise SystemExit(main())
