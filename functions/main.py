# The Cloud Functions for Firebase SDK to create Cloud Functions and set up triggers.
from firebase_functions import firestore_fn, https_fn
from firebase_functions import options

# The Firebase Admin SDK to access Cloud Firestore.
from firebase_admin import initialize_app, firestore, messaging
import google.cloud.firestore

import requests
from bs4 import BeautifulSoup
import hashlib
import random

app = initialize_app()

# Activity 類別，和 Dart 版一致
class Activity:
    def __init__(self, title, href, source, img_url):
        self.title = title
        self.url = href
        self.source = source
        self.imgUrl = img_url
        self.likeBy = []
        self.groupId = None
        self.groupLimit = 5
        self.date = None
        # 用 URL + 標題生成唯一 ID
        self.id = str(hashlib.md5(f"{title}_{href}".encode("utf-8")).hexdigest())
    
    def to_dict(self):
        return {
            "title": self.title,
            "url": self.url,
            "source": self.source,
            "imageUrl": self.imgUrl,
            "likedBy": self.likeBy,
            "groupId": self.groupId,
            "groupLimit": self.groupLimit,
            "date": self.date,
            "createdAt": firestore.SERVER_TIMESTAMP,
        }

def fetch_detail_img_if_valid(url):
    try:
        headers = {
            "User-Agent": "Mozilla/5.0"
        }
        response = requests.get(url, headers=headers)
        if response.status_code != 200:
            return ''

        soup = BeautifulSoup(response.text, 'html.parser')
        img_url = soup.select('#relateImg0 > div > img')
        if not img_url:
            return 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQXwODiLQvRBA1BDszB7csUFnWYDEie3epJlQ&s'

        return "https://osa.nycu.edu.tw" + img_url[0]['src']
    except Exception as e:
        print(f'抓取活動詳細頁失敗: {e}')
        return 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQXwODiLQvRBA1BDszB7csUFnWYDEie3epJlQ&s'

def fetch_nycu_activities():
    firestore_client: google.cloud.firestore.Client = firestore.client()

    url = 'https://osa.nycu.edu.tw/osa/ch/app/data/list?module=nycu0085&id=3494'
    headers = {
        "User-Agent": "Mozilla/5.0"
    }
    response = requests.get(url, headers=headers)

    if response.status_code != 200:
        raise Exception('網站請求失敗')

    soup = BeautifulSoup(response.text, 'html.parser')
    items = soup.select('div.newslist > ul > li')
    print(f"nycu get li number: {len(items)}")
    for item in items:
        a_tag = item.select_one('a')
        if a_tag:
            info_div = a_tag.select_one('div.info')
            category = ''
            p_tags = info_div.select('p')
            for p in p_tags:
                text = p.get_text(strip=True)
                if text.startswith('分類：'):
                    category = text.replace('分類：', '').strip()
                    break
            if category not in ['校外訊息', '校內活動']:
                continue
            title = a_tag.get('title', '')
            href = "https://osa.nycu.edu.tw" + a_tag.get('href', '')
            if not ("徵" in title):
                img_url = fetch_detail_img_if_valid(href)
                activity = Activity(title, href, "nycu", img_url)
                doc_ref = firestore_client.collection('activities').document(activity.id)
                doc = doc_ref.get()
                if not doc.exists:
                    doc_ref.set(activity.to_dict())
                    print(f"add nycu: {activity.id}")
                else:
                    continue
            else:
                continue
        else:
            continue

    print("nycu activities fetched successfully.")

def fetch_hsin_activities():
    firestore_client: google.cloud.firestore.Client = firestore.client()
    url = "https://tjm.tainanoutlook.com/hsinchu"
    headers = {
        "User-Agent": "Mozilla/5.0"
    }
    response = requests.get(url, headers=headers)

    if response.status_code == 200:
        soup = BeautifulSoup(response.text, "html.parser")
        a_title = soup.select('#blazy-3d03bf26a8e-1 > li > div > div > span > div > a > img')
        a_tags = soup.select('#blazy-3d03bf26a8e-1 > li > div > div > span > div > div > h3 > a')
        print(f"hsin get a number : {len(a_title)}")
        for i in range(len(a_title)):
            title = a_title[i].get('title')
            href = "https://tjm.tainanoutlook.com" + a_tags[i].get('href')
            img_url = a_title[i].get('src')
            if "https://i.imgur.com" in img_url:
                img_url = None
            activity = Activity(title, href, "hsinchu", img_url)
            doc_ref = firestore_client.collection('activities').document(activity.id)
            doc = doc_ref.get()
            if not doc.exists:
                doc_ref.set(activity.to_dict())
                print(f"add hsin: {activity.id}")

def fetch_nthu_activities():
    firestore_client: google.cloud.firestore.Client = firestore.client()
    ajax_url = [
        "https://bulletin.site.nthu.edu.tw/app/index.php?Action=mobileloadmod&Type=mobile_rcg_mstr&Nbr=5083",
        "https://bulletin.site.nthu.edu.tw/app/index.php?Action=mobileloadmod&Type=mobile_rcg_mstr&Nbr=5085"
    ]
    headers = {
        "User-Agent": "Mozilla/5.0"
    }
    for url in ajax_url:
        response = requests.get(url, headers=headers)
        if response.status_code == 200:
            soup = BeautifulSoup(response.text, "html.parser")
            a_tags = soup.select('a')
            print(f"nthu get a number: {len(a_tags)}")
            for a in a_tags:
                href = a.get('href')
                title = a.get('title') or a.text.strip()
                if title != "更多..." and not ("徵" in title) and not ("Recruitment" in title) and not ("招募" in title):
                    activity = Activity(
                        title, href, "nthu",
                        'https://upload.wikimedia.org/wikipedia/commons/thumb/5/5c/NTHU_Round_Seal.svg/1200px-NTHU_Round_Seal.svg.png'
                    )
                    doc_ref = firestore_client.collection('activities').document(activity.id)
                    doc = doc_ref.get()
                    if not doc.exists:
                        doc_ref.set(activity.to_dict())
                        print(f"add nthu: {activity.id}")

@https_fn.on_request()
def fetch_activities(req: https_fn.Request) -> https_fn.Response:
    fetch_nycu_activities()
    fetch_hsin_activities()
    fetch_nthu_activities()
    return https_fn.Response("Activities fetched successfully.")

@https_fn.on_request()
def create_restaurant_activity(req: https_fn.Request) -> https_fn.Response:
    """Create a new restaurant activity in Firestore."""
    firestore_client: google.cloud.firestore.Client = firestore.client()
    
    restaurant_name = ["全美自助餐", "素怡園"]
    restaurant = "中午吃" + restaurant_name[random.randint(0, len(restaurant_name) - 1)]
    activity = Activity(
        restaurant, None, "restaurant",
        'https://img.shoplineapp.com/media/image_clips/64ef01e8c27149001420b87e/original.jpg?1693385191'
    )
    doc_ref = firestore_client.collection('activities').document(activity.id)
    doc = doc_ref.get()
    if not doc.exists:
        doc_ref.set(activity.to_dict())
        print(f"add restaurant: {activity.id}")
    
    return https_fn.Response(f"Restaurant activity {activity.id} created successfully.")

@https_fn.on_call()
def sendNotification(request):
    """Send FCM notification to a specific user."""
    # 檢查認證
    if not request.auth:
        raise https_fn.HttpsError("unauthenticated", "必須登入才能發送通知")

    # 提取參數
    data = request.data
    fcm_token = data.get("fcmToken")
    title = data.get("title")
    body = data.get("body")
    notification_data = data.get("data", {})

    if not fcm_token or not title or not body:
        raise https_fn.HttpsError("invalid-argument", "缺少必要參數：fcmToken、title、body")

    # 構建 FCM 訊息
    message = messaging.Message(
        token=fcm_token,
        notification=messaging.Notification(
            title=title,
            body=body,
        ),
        data=notification_data,
        android=messaging.AndroidConfig(
            priority="high",
        ),
        apns=messaging.APNSConfig(
            payload=messaging.APNSPayload(
                aps=messaging.Aps(badge=1, sound="default")
            ),
        ),
    )

    try:
        # 發送通知
        messaging.send(message)
        return {"success": True, "message": "通知發送成功"}
    except Exception as e:
        print(f"發送通知失敗: {str(e)}")
        raise https_fn.HttpsError("internal", f"發送通知失敗: {str(e)}")