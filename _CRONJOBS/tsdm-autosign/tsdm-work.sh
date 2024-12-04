docker run --rm -it -v "$(pwd):/app" python:3.6 /bin/bash -c "pip install -r /app/requirements.txt && python /app/SCF_sign.py && python /app/SCF_work.py"

