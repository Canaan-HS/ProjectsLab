import flet as ft

from modules import View


def main(page: ft.Page) -> None:
    View(page)


if __name__ == "__main__":
    ft.run(main)
