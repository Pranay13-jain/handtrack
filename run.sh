#!/bin/bash
# Start HandTrack from anywhere: ./run.sh  (extra options are passed on, e.g. ./run.sh --dry-run)
# Creates or repairs the Python environment automatically on first run.
cd "$(dirname "$0")" || exit 1

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 not found. Install Python 3 from https://www.python.org/downloads/"
    exit 1
fi

if ! .venv/bin/python -c "import cv2, mediapipe, pyautogui" >/dev/null 2>&1; then
    echo "Setting up the Python environment (first run only, takes a minute)..."
    rm -rf .venv
    python3 -m venv .venv || exit 1
    .venv/bin/python -m pip install --quiet --upgrade pip
    .venv/bin/python -m pip install --quiet -r requirements.txt || exit 1
fi

if [ ! -f handtrack/models/hand_landmarker.task ]; then
    echo "Downloading the hand model..."
    mkdir -p handtrack/models
    curl -sSfL -o handtrack/models/hand_landmarker.task \
        https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task || exit 1
fi

export GLOG_minloglevel=2          # hide MediaPipe's internal INFO logs
exec .venv/bin/python -m handtrack "$@"
