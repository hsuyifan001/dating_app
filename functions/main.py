from firebase_functions import https_fn
from firebase_admin import initialize_app, firestore
import google.cloud.firestore
import requests
from bs4 import BeautifulSoup
import hashlib

# 初始化 Firebase Admin
app = initialize_app()

# Activity 類別，和 Dart 版一致
class Activity:
    def __init__(self, title, href, location):
        self.title = title
        self.href = href
        self.location = location
        # 用 URL + 標題生成唯一 ID
        self.id = hashlib.md5(f"{title}_{href}".encode("utf-8")).hexdigest()

    def to_dict(self):
        return {
            "title": self.title,
            "href": self.href,
            "location": self.location,
        }

@https_fn.on_request()
def fetch_and_save_hsin_activities(req: https_fn.Request) -> https_fn.Response:
    url = 'https://tjm.tainanoutlook.com/hsinchu'
    firestore_client: google.cloud.firestore.Client = firestore.client()

    # 發送 HTTP 請求
    try:
        response = requests.get(url, headers={
            'User-Agent': 'Mozilla/5.0',
        })
    except Exception as e:
        return https_fn.Response(f"Error fetching {url}: {str(e)}", status=500)

    if response.status_code != 200:
        return https_fn.Response(f"Error fetching {url} - Status: {response.status_code}", status=500)

    # 解析 HTML
    soup = BeautifulSoup(response.text, 'html.parser')

    img_elements = soup.select('#blazy-3d03bf26a8e-1 > li > div > div > span > div > a > img')
    a_elements = soup.select('#blazy-3d03bf26a8e-1 > li > div > div > span > div > a')

    saved_count = 0
    skipped_count = 0

    for img, a in zip(img_elements, a_elements):
        href = a.get('href')
        title = img.get('title') or a.get_text(strip=True) or "無標題"

        if not href:
            continue

        activity = Activity(title, href, 'hsinchu')

        doc_ref = firestore_client.collection('activities').document(activity.id)
        doc = doc_ref.get()

        if not doc.exists:
            doc_ref.set(activity.to_dict())
            saved_count += 1
        else:
            skipped_count += 1

    return https_fn.Response(f"Saved: {saved_count}, Skipped: {skipped_count}", status=200)
