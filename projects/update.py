#!/usr/bin/env python3

import shutil
import subprocess
import tempfile
import tomllib
import argparse
from pathlib import Path


CONFIG_FILE = "projects.toml"
CHANGELOG_DIR = Path("./changelogs")


def run(cmd, cwd=None, stdout=None):
    print("+", " ".join(cmd))
    subprocess.run(
        cmd,
        cwd=cwd,
        stdout=stdout,
        stderr=subprocess.STDOUT if stdout else None,
        check=True,
        text=True,
    )


def clean_dir(path: Path):
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def copy_without_git(src: Path, dst: Path):
    clean_dir(dst)

    for item in src.iterdir():
        if item.name == ".git":
            continue

        target = dst / item.name

        if item.is_dir():
            shutil.copytree(item, target, ignore=shutil.ignore_patterns(".git"))
        else:
            shutil.copy2(item, target)


def process_project(project: dict):
    name = project["name"]
    dst_path = Path(project["path"])
    url = project["url"]
    branch = project["branch"]
    start_commit = project["start_commit"]
    recurse_submodules = project.get("recurse_submodules", False)

    print(f"\n=== {name} ===")

    with tempfile.TemporaryDirectory(prefix="upstream_") as tmp:
        repo_path = Path(tmp) / "repo"

        clone_cmd = [
            "git",
            "clone",
            "--branch", branch,
            "--single-branch",
        ]

        if recurse_submodules:
            clone_cmd.append("--recurse-submodules")

        clone_cmd.extend([url, str(repo_path)])
        run(clone_cmd)

        if recurse_submodules:
            # Если в репозитории есть сабмодули, подтягиваем их рекурсивно.
            run([
                "git",
                "submodule",
                "update",
                "--init",
                "--recursive",
            ], cwd=repo_path)

        CHANGELOG_DIR.mkdir(parents=True, exist_ok=True)
        log_file = CHANGELOG_DIR / f"{name}.log"

        # Важно:
        # start_commit^..HEAD включает сам start_commit.
        # start_commit..HEAD НЕ включает сам start_commit.
        log_range = f"{start_commit}^..HEAD"

        with log_file.open("w", encoding="utf-8") as f:
            run([
                "git",
                "log",
                "--reverse",
                "--date=iso",
                "--stat",
                "-p",
                log_range,
            ], cwd=repo_path, stdout=f)

        git_dir = repo_path / ".git"
        if git_dir.exists():
            shutil.rmtree(git_dir)

        copy_without_git(repo_path, dst_path)

        print(f"Saved source: {dst_path}")
        print(f"Saved changelog: {log_file}")


def select_projects_interactive(projects: list[dict]) -> list[dict]:
    print("\nInteractive mode enabled.")
    print("Select a project to update:")

    for idx, project in enumerate(projects, start=1):
        print(f"  {idx}. {project['name']} ({project['path']})")

    print("  a. Update all projects")
    print("  q. Quit")

    while True:
        choice = input("\nEnter your choice: ").strip().lower()

        if choice == "a":
            return projects
        if choice == "q":
            print("No projects selected. Exiting.")
            return []
        if choice.isdigit():
            index = int(choice) - 1
            if 0 <= index < len(projects):
                return [projects[index]]

        print("Invalid choice. Enter a number, 'a', or 'q'.")


def main():
    parser = argparse.ArgumentParser(
        description="Update local project mirrors and changelogs from upstream sources."
    )
    parser.add_argument(
        "-i",
        "--interactive",
        action="store_true",
        help="Enable interactive mode to update a specific project.",
    )
    args = parser.parse_args()

    with open(CONFIG_FILE, "rb") as f:
        config = tomllib.load(f)

    projects = config["projects"]

    if args.interactive:
        projects = select_projects_interactive(projects)

    for project in projects:
        process_project(project)


if __name__ == "__main__":
    main()
