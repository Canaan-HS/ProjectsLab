import psutil

physical_cores = psutil.cpu_count(logical=False)
logical_cores_from_psutil = psutil.cpu_count(logical=True)

MAX_WORKERS = physical_cores * logical_cores_from_psutil
