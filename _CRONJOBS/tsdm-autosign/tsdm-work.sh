#/bin/bash
# author: df
# date: 2024-12-4
# desc: tsdm自动签到脚本。 
# 修改自 https://github.com/trojblue/TSDM-coin-farmer 和 https://github.com/trojblue/TSDM-coin-farmer/pull/20
# 抽取其中重點部分，並將其修改為適合local執行的腳本。
docker run --rm -it -v "$(pwd):/app" python:3.6 /bin/bash -c "pip install -r /app/requirements.txt && cd /app && python /app/SCF_sign.py && python /app/SCF_work.py" > output.log 2>&1


