"""Render the real account template with a fixed, non-secret owner fixture."""
from pathlib import Path
import sys
from flask import Flask, render_template


def main():
    root = Path(__file__).resolve().parents[1]
    app = Flask("account-fixture", template_folder=str(root / "server/account/templates"), static_folder=None)
    with app.app_context():
        html = render_template("account.html", mode="home", username="traffic-fixture-owner")
    sys.stdout.buffer.write(html.encode("utf-8"))


if __name__ == "__main__":
    main()
