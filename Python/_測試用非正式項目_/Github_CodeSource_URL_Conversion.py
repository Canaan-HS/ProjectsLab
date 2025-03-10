from urllib.parse import urlparse, unquote
import re

class Conversion:
    def __init__(self, url):
        self.url = url
        self.domain = "https://raw.githubusercontent.com"
        self.github = r"^https:\/\/github\.com\/.+\/blob\/.*"
        self.convert()

    def convert(self):
        if re.match(self.github, self.url):
            parsed_url = urlparse(self.url)
            convert = f"{self.domain}{parsed_url.path.replace('/blob/', '/refs/heads/')}"
            print(f'"{unquote(convert)}"')
        else:
            print("錯誤的網址")