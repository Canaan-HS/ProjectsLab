from Script import DI
import asyncio
import httpx

# https://pass.levelinfinite.com/

""" 需要的 cookie

lip_uid
lip_channelid
lip_user_name
lip_openid
lip_token

"""

cookies = DI.get_json("Cookies.json")

headers = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36",
}


CheckInTask = {
    "每日簽到": {
        "task_id": "15",
        "task_url": "https://api-pass.levelinfinite.com/api/rewards/proxy/lipass/Points/DailyCheckIn",
    },
    "活動階段": {
        "task_id": "55",
        "task_url": "https://api-pass.levelinfinite.com/api/rewards/proxy/lipass/Points/DailyStageCheckIn",
    },
}

StateTask = {
    "查看 Points": "https://api-pass.levelinfinite.com/api/rewards/proxy/lipass/Points/GetUserTotalPoints",
    "查看任務狀態": "https://api-pass.levelinfinite.com/api/rewards/proxy/lipass/Points/GetTaskListWithStatusV2",
}


async def async_http_get(url, id) -> dict:
    async with httpx.AsyncClient(http2=True) as client:
        response = await client.post(url, json=id, headers=headers, cookies=cookies)
        return response.json()


async def CheckIn():
    works = [
        async_http_get(work["task_url"], {"task_id": work["task_id"]})
        for work in CheckInTask.values()
    ]
    results = await asyncio.gather(*works)
    print(results)


asyncio.run(CheckIn())

# client = httpx.Client(http2=True)
# response = client.post(StateTask["查看 Points"], headers=headers, cookies=cookies)
# print(response.json()['data']['total_points'])

# response = client.post(StateTask["查看任務狀態"], headers=headers, cookies=cookies)
# for state in response.json()['data']['tasks']:
    # print(state['task_name'], state['task_id'], state['reward_infos'][0]['is_completed'])