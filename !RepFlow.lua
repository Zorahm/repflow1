import telebot
from telebot.types import InlineKeyboardMarkup, InlineKeyboardButton
import os
import logging
import schedule
import threading
import time
import sqlite3
from datetime import datetime
import math
import re
import sys
import signal
import pytz
import json

schedule = {
    "четная": {
        "Понедельник": ["Литература", "Литература"],
        "Вторник": ["Информатика", "Информатика", "Математика", "Математика"],
        "Среда": ["История", "История", "Математика", "Математика"],
        "Четверг": ["Английский", "Английский", "Химия", "Химия"],
        "Пятница": ["Техника личной презентации", "Техника личной презентации"]
    },
    "нечетная": {
        "Понедельник": ["Литература", "Литература"],
        "Вторник": ["Информатика", "Информатика", "Математика", "Математика"],
        "Среда": ["География", "Биология", "Обществознание", "Обществознание"],
        "Четверг": ["Физика", "Физика", "Физическая культура"],
        "Пятница": ["Биология", "География", "Русский язык", "Русский язык"]
    }
}

lesson_times = [
    ("10:10", "11:40"),
    ("11:50", "13:20"),
    ("13:50", "15:20"),
    ("15:30", "17:00")
]

def run_bot():
    while True:
        try:
            # Ваш основной код бота
            print("Бот запущен")
            bot.polling(none_stop=True)
        except Exception as e:
            print(f"Критическая ошибка: {e}. Перезапуск через 5 секунд...")
            time.sleep(5)
            os.execv(sys.executable, ['python'] + sys.argv)

# Получаем путь к директории, где находится основной файл скрипта
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, 'homework_bot.db')

# Инициализация базы данных
def init_db():
    conn = sqlite3.connect(DB_PATH)  # Используем путь DB_PATH
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS users (
            chat_id TEXT PRIMARY KEY,
            notification_time TEXT DEFAULT '09:00',
            notification_days TEXT DEFAULT 'monday'
        )
    ''')
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS homework (
            month TEXT,
            week INTEGER,
            homework_text TEXT,
            file_id TEXT,
            PRIMARY KEY (month, week)
        )
    ''')
    conn.commit()
    conn.close()
    migrate_db()

def migrate_db():
    conn = sqlite3.connect('homework_bot.db')
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(homework)")
    columns = [column[1] for column in cursor.fetchall()]
    if 'file_id' not in columns:
        cursor.execute("ALTER TABLE homework ADD COLUMN file_id TEXT")
        conn.commit()
    conn.close()

BOT_TOKEN ='7611154594:AAFLXYNHBIOY9-U01wdn6-5x6AG48ZhJrvA'
bot = telebot.TeleBot(BOT_TOKEN)
logging.basicConfig(level=logging.INFO, filename='bot.log', filemode='a')

MONTHS = ["Сентябрь", "Октябрь", "Ноябрь", "Декабрь", "Январь", "Февраль", "Март", "Апрель", "Май", "Июнь"]
DAYS_OF_WEEK = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
ADMIN_IDS = [5629302452, 987654321]

user_ids = set()

# Сохранение в файл
with open("user_ids.json", "w") as f:
    json.dump(list(user_ids), f)

# Загрузка из файла при старте бота
try:
    with open("user_ids.json", "r") as f:
        user_ids = set(json.load(f))
except FileNotFoundError:
    user_ids = set()
    
@bot.message_handler(commands=['broadcast'])
def admin_broadcast(message):
    if message.chat.id in ADMIN_IDS:
        bot.send_message(ADMIN_IDS[0], "Введите текст для рассылки:")
        bot.register_next_step_handler(message, process_broadcast)
    else:
        bot.send_message(message.chat.id, "Команда доступна только администратору.")

def process_broadcast(message):
    text = message.text
    broadcast_message(text)
    bot.send_message(ADMIN_IDS[0], "Сообщение успешно отправлено!")


@bot.message_handler(commands=['report'])
def handle_report(message):
    bot.send_message(message.chat.id, "Опишите вашу проблему или предложение:")
    bot.register_next_step_handler(message, process_report)

def process_report(message):
    report_text = message.text
    user_id = message.chat.id
    username = message.from_user.username or "Без имени"

    # Отправка админу
    admin_message = f"📢 Новый отчет от пользователя @{username} (ID: {user_id}):\n\n{report_text}"
    try:
        bot.send_message(ADMIN_IDS[0], admin_message)
        bot.send_message(user_id, "Спасибо за ваш отчет! Мы рассмотрим его в ближайшее время.")
    except Exception as e:
        bot.send_message(user_id, "Не удалось отправить отчет. Попробуйте позже.")
        print(f"Ошибка отправки отчета: {e}")
        logging.error(f"Ошибка отправки отчета: {e}")

@bot.message_handler(commands=['view_reports'])
def view_reports(message):
    if message.chat.id in ADMIN_IDS:
        try:
            with open("reports.json", "r") as f:
                reports = f.readlines()
            if reports:
                bot.send_message(ADMIN_IDS[0], "📄 Список отчетов:")
                for report in reports:
                    bot.send_message(ADMIN_IDS[0], report)
            else:
                bot.send_message(ADMIN_IDS[0], "Нет новых отчетов.")
        except FileNotFoundError:
            bot.send_message(ADMIN_IDS[0], "Файл отчетов пока пуст.")
    else:
        bot.send_message(message.chat.id, "Команда доступна только администратору.")

# ------------------------------
# БАЗА ДАННЫХ: ДОМАШНЕЕ ЗАДАНИЕ
# ------------------------------
def save_homework(month, week, homework_text):
    conn = sqlite3.connect('homework_bot.db')
    cursor = conn.cursor()
    cursor.execute("""
        INSERT OR REPLACE INTO homework (month, week, homework_text)
        VALUES (?, ?, ?)
    """, (month, week, homework_text))
    conn.commit()
    conn.close()

def get_homework(month, week):
    conn = sqlite3.connect('homework_bot.db')
    cursor = conn.cursor()
    cursor.execute("SELECT homework_text FROM homework WHERE month = ? AND week = ?", (month, week))
    result = cursor.fetchone()
    conn.close()
    return result[0] if result else None

def get_weeks_with_homework(month):
    conn = sqlite3.connect('homework_bot.db')
    cursor = conn.cursor()
    cursor.execute("SELECT DISTINCT week FROM homework WHERE month = ?", (month,))
    weeks = cursor.fetchall()
    conn.close()
    print(f"Недели для месяца {month}: {weeks}")  # Добавлено для отладки
    return [week[0] for week in weeks]


@bot.message_handler(commands=['stop_bot'])
def stop_bot(message):
    # Проверяем, является ли пользователь администратором (если нужно)
    if message.chat.id not in ADMIN_IDS:
        bot.reply_to(message, "У вас нет прав для выполнения этой команды.")
        return

    bot.reply_to(message, "Бот останавливается...")
    
    # Останавливаем бота
    sys.exit()  # Завершаем выполнение программы

def signal_handler(sig, frame):
    print("Бот завершен.")
    sys.exit(0)

signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

# ------------------------------
# /start
# ------------------------------
@bot.message_handler(commands=['start'])
def send_welcome(message):
    # Основные команды для всех пользователей
    info_msg = (
        "👋 Добро пожаловать!\n"
        "Я бот для помощи в учебе и других задачах.\n\n"
        "📋 Доступные команды:\n\n"
        "📚 Домашние задания:\n"
        "/homework - Посмотреть домашнее задание\n"
        "/show_homework <месяц> <неделя> - Задание за определенную дату\n\n"
        "📖 Расписание:\n"
        "/current_lesson - Какая пара идет сейчас\n\n"
        "🧮 Калькулятор:\n"
        "/calc - Запустить калькулятор\n"
        "/calc_help - Справка по калькулятору\n\n"
        "🛠️ Прочее:\n"
        "/report - Отправить сообщение о проблеме или предложении\n"
        "/start - Показать это сообщение\n"
        "/help - Получить справку по боту\n\n"
        "📢 Уведомления:\n"
        "/subscribe - Подписаться на рассылку уведомлений\n"
        "/unsubscribe - Отписаться от рассылки уведомлений\n\n"
        "✨ Советы:\n"
        "1. Используйте точные команды, чтобы получить желаемый результат.\n"
        "2. Если что-то не работает, сообщите через /report."
    )
    
    # Проверка, является ли пользователь администратором
    if message.from_user.id in ADMIN_IDS:
        info_msg += "\n\n🔧 Админские команды:\n"
        info_msg += "/broadcast - Отправить сообщение всем пользователям\n"
        info_msg += "/add_homework - Добавить домашнее задание\n"

    # Отправляем сообщение с доступными командами
    bot.send_message(message.chat.id, info_msg)


@bot.message_handler(commands=['help'])
def send_help(message):
    bot.send_message(message.chat.id, "Я могу выполнять различные математические операции. Просто введите выражение или используйте клавиатуру для выбора операции. Вот что я поддерживаю:\n- Сложение, вычитание, умножение, деление\n- Квадратный корень, степень\n- Логарифмы и тригонометрия")

# ------------------------------
# /calc_help - отображение справки по калькулятору
# ------------------------------
@bot.message_handler(commands=['calc_help'])
def handle_calc_help(message):
    # Отправляем подробную информацию о калькуляторе
    bot.send_message(
        message.chat.id,
        "Привет! Я калькулятор. Вот что ты можешь со мной делать:\n\n"
        "1. Используй стандартные математические операторы:\n"
        "- Сложение: +\n"
        "- Вычитание: -\n"
        "- Умножение: *\n"
        "- Деление: /\n"
        "- Степень: ^ (например, 2^3)\n"
        "- Квадратный корень: sqrt (например, sqrt 16)\n"
        "- Факториал: ! (например, 5!)\n"
        "- Логарифм: log(x, base) (например, log(10, 2))\n"
        "- Тригонометрические функции: sin(x), cos(x), tan(x) (например, sin(30))\n\n"
        "2. Примеры ввода:\n"
        "- 3 + 5\n"
        "- 10 * 2\n"
        "- sqrt 25\n"
        "- 2^3\n"
        "- 5!\n"
        "- log(10, 2)\n"
        "- sin(30)\n\n"
        "3. Вводи выражение и я вычислю результат!"
    )

# ------------------------------
# /calc - выполнение вычислений
# ------------------------------
@bot.message_handler(commands=['calc'])
def handle_calc(message):
    bot.send_message(message.chat.id, "Введите математическое выражение для вычисления:")
    bot.register_next_step_handler(message, process_calculation)

def process_calculation(message):
    try:
        expression = message.text.strip().lower()  # Приводим текст к нижнему регистру

        # Преобразуем выражение для поддержки новых операций
        expression = expression.replace('^', '**')  # Заменяем ^ на **
        expression = expression.replace('sqrt', 'math.sqrt')  # Заменяем sqrt на math.sqrt
        expression = expression.replace('log', 'math.log')  # Заменяем log на math.log
        expression = expression.replace('sin', 'math.sin')  # Заменяем sin на math.sin
        expression = expression.replace('cos', 'math.cos')  # Заменяем cos на math.cos
        expression = expression.replace('tan', 'math.tan')  # Заменяем tan на math.tan

        # Обработка sqrt для добавления нужных скобок
        expression = re.sub(r'(math\.sqrt)(\s*(\d+))', r'\1(\2)', expression)  # Преобразует "sqrt 25" в "math.sqrt(25)"

        # Закрытие скобок для других математических функций, если это нужно
        expression = re.sub(r'(math\.\w+)(\d+)', r'\1(\2)', expression)

        # Обработка факториала
        while '!' in expression:
            match = re.search(r'(\d+)!', expression)
            if match:
                number = int(match.group(1))
                factorial_result = math.factorial(number)
                expression = expression.replace(f"{number}!", str(factorial_result))
            else:
                break

        # Вычисление результата
        result = eval(expression)
        bot.send_message(message.chat.id, f"Результат: {result}")
    except Exception as e:
        bot.send_message(message.chat.id, f"Произошла ошибка: {str(e)}")

# ------------------------------
# ДОБАВЛЕНИЕ ДОМАШНЕГО ЗАДАНИЯ
# ------------------------------
@bot.message_handler(commands=['add_homework'])
def add_homework(message):
    if message.chat.id not in ADMIN_IDS:
        bot.reply_to(message, "У вас нет прав для выполнения этой команды.")
        return

    bot.send_message(message.chat.id, 
                     "Введите месяц, неделю и текст задания в формате:\nМесяц, Неделя, Задание",
                     parse_mode="Markdown")
    bot.register_next_step_handler(message, process_add_homework)

def process_add_homework(message):
    try:
        data = message.text.split(", ")
        if len(data) < 3:
            raise ValueError("Неверный формат ввода.")
        
        month, week, homework_text = data[0], int(data[1]), message.text.split(", ", 2)[2]

        if month not in MONTHS:
            bot.reply_to(message, "Указан неверный месяц. Попробуйте снова.")
            return

        save_homework(month, week, homework_text)
        bot.reply_to(message, f"Задание для {month}, Неделя {week} сохранено.")
        
    except Exception as e:
        bot.reply_to(message, f"Ошибка: {e}")
# ------------------------------
# ПОКАЗ ДОМАШНЕГО ЗАДАНИЯ
# ------------------------------
@bot.message_handler(commands=['show_homework'])
def show_homework(message):
    try:
        data = message.text.split(" ", 2)
        if len(data) != 3:
            bot.reply_to(message, "Используйте формат: /show_homework месяц неделя")
            return

        _, month, week = data
        week = int(week)

        homework = get_homework(month, week)
        if homework:
            bot.send_message(message.chat.id, f"📚 Домашнее задание для {month}, Неделя {week}:\n{homework}")
        else:
            bot.send_message(message.chat.id, f"Задание для {month}, Неделя {week} не найдено.")
    except Exception as e:
        bot.reply_to(message, f"Ошибка: {e}")

# ------------------------------
# КНОПКИ ДЛЯ ДОСТУПА К ДОМАШНЕМУ ЗАДАНИЮ
# ------------------------------
def create_month_buttons():
    markup = InlineKeyboardMarkup()
    for month in MONTHS:
        markup.add(InlineKeyboardButton(month, callback_data=f"month_{month}"))
    return markup

def create_week_buttons(month):
    weeks = get_weeks_with_homework(month)
    markup = InlineKeyboardMarkup()
    for week in weeks:
        markup.add(InlineKeyboardButton(f"Неделя {week}", callback_data=f"week_{month}_{week}"))
    return markup

# ------------------------------
# /homework
# ------------------------------
@bot.message_handler(commands=['homework'])
def homework_menu(message):
    print(f"Получена команда /homework от {message.chat.id}")  # Для отладки
    bot.send_message(
        message.chat.id,
        "Выберите месяц, чтобы посмотреть задания:",
        reply_markup=create_month_buttons()
    )

@bot.callback_query_handler(func=lambda call: call.data.startswith("month_"))
def handle_month(call):
    try:
        month = call.data.split("_")[1]
        markup = create_week_buttons(month)
        bot.edit_message_text(
            f"Вы выбрали {month}. Выберите неделю:",
            chat_id=call.message.chat.id,
            message_id=call.message.message_id,
            reply_markup=markup
        )
    except Exception as e:
        bot.send_message(call.message.chat.id, "Произошла ошибка при обработке команды.")
        logging.error(f"Ошибка в handle_month: {e}, {str(call.data)}")  # Логируем дополнительную информацию

@bot.callback_query_handler(func=lambda call: call.data.startswith("week_"))
def handle_week(call):
    _, month, week = call.data.split("_")
    week = int(week)
    homework = get_homework(month, week)
    if homework:
        bot.send_message(call.message.chat.id, f"📚 Домашнее задание для {month}, Неделя {week}:\n\n{homework}")
    else:
        bot.send_message(call.message.chat.id, f"Задание для {month}, Неделя {week} не найдено.")

# Функция для отправки рассылки
def send_broadcast(message_text):
    try:
        with open("subscribers.json", "r") as f:
            subscribers = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        subscribers = []
    
    for user_id in subscribers:
        try:
            bot.send_message(user_id, message_text)
        except Exception as e:
            print(f"Не удалось отправить сообщение пользователю {user_id}: {e}")

# Обработчик команды /broadcast
@bot.message_handler(commands=['broadcast'])
def handle_broadcast(message):
    if message.chat.id == ADMIN_IDS[0]:  # Проверка на администратора
        bot.send_message(message.chat.id, "📝 Напишите текст для рассылки.")
        
        # Переход к следующему состоянию — ожидание текста
        bot.register_next_step_handler(message, broadcast_message)
    else:
        bot.send_message(message.chat.id, "❌ У вас нет прав для использования этой команды.")

def broadcast_message(message_text):
    """
    Функция для отправки сообщения всем подписанным пользователям.
    Если передан текст сообщения, отправляет его всем подписанным пользователям.
    """
    # Если message_text — это строка, используем её как текст
    if isinstance(message_text, str):
        text = message_text
    # Если message_text — это объект Message от Telegram, извлекаем текст
    elif hasattr(message_text, 'text'):
        text = message_text.text
    else:
        # Если это не строка и не объект сообщения Telegram, выдаем ошибку
        raise ValueError("Передан некорректный параметр для рассылки.")

    # Отправляем текст всем пользователям, которые подписаны на рассылку
    for user_id in subscribed_users:
        try:
            bot.send_message(user_id, text)
            print(f"Сообщение отправлено пользователю {user_id}")
        except Exception as e:
            print(f"Ошибка при отправке сообщения пользователю {user_id}: {e}")


# Функция для сохранения ID пользователя
def save_user_id(user_id):
    try:
        with open("subscribers.json", "r") as f:
            subscribers = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        subscribers = []
    
    if user_id not in subscribers:
        subscribers.append(user_id)
        with open("subscribers.json", "w") as f:
            json.dump(subscribers, f)

@bot.message_handler(commands=['subscribe'])
def subscribe(message):
    user_id = message.chat.id
    save_user_id(user_id)
    bot.send_message(user_id, "✅ Вы успешно подписались на рассылку!")

@bot.message_handler(commands=['unsubscribe'])
def unsubscribe(message):
    user_id = message.chat.id
    try:
        with open("subscribers.json", "r") as f:
            subscribers = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        subscribers = []
    
    if user_id in subscribers:
        subscribers.remove(user_id)
        with open("subscribers.json", "w") as f:
            json.dump(subscribers, f)
        bot.send_message(user_id, "❌ Вы отписались от рассылки.")
    else:
        bot.send_message(user_id, "❌ Вы не были подписаны на рассылку.")


# Загрузка данных
def load_users():
    # Здесь можно подключить вашу базу данных или файл
    try:
        with open("user_data.json", "r") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}

# Сохранение данных
def save_users(data):
    with open("user_data.json", "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=4)

@bot.message_handler(commands=['set_week'])
def set_week(message):
    # Проверка, является ли пользователь админом
    if message.from_user.id not in ADMIN_IDS:
        bot.send_message(message.chat.id, "❌ У вас нет прав для использования этой команды.")
        return

    try:
        week_type = message.text.split()[1].strip().lower()  # Получаем тип недели из команды
        if week_type in ['четная', 'нечетная']:
            # Сохраняем тип недели в файл
            with open("week_type.txt", "w") as f:
                f.write(week_type)
            bot.send_message(message.chat.id, f"✅ Текущая неделя установлена: {week_type.capitalize()}")
        else:
            bot.send_message(message.chat.id, "❌ Укажите тип недели: четная или нечетная.")
    except IndexError:
        bot.send_message(message.chat.id, "❌ Укажите тип недели после команды. Например: /set_week четная")

@bot.message_handler(commands=['current_lesson'])
def current_lesson(message):
    try:
        # Читаем текущий тип недели
        with open("week_type.txt", "r") as f:
            week_type = f.read().strip().lower()

        # Определяем текущий день недели и время
        moscow_tz = pytz.timezone('Europe/Moscow')
        current_time = datetime.now(moscow_tz)
        weekday = current_time.strftime("%A").lower()
        current_time_str = current_time.strftime("%H:%M")

        # Определяем текущую пару
        for i, (start, end) in enumerate(lesson_times):
            if start <= current_time_str <= end:
                lesson_index = i
                start_time = datetime.strptime(start, "%H:%M")
                end_time = datetime.strptime(end, "%H:%M")
                current_time_obj = datetime.strptime(current_time_str, "%H:%M")
                
                # Рассчитываем прошедшее и оставшееся время
                elapsed_time = (current_time_obj - start_time).seconds // 60
                remaining_time = (end_time - current_time_obj).seconds // 60
                break
        else:
            bot.send_message(message.chat.id, "❌ Сейчас нет пар.")
            return

        # Получаем предмет текущей пары
        lessons_today = schedule.get(week_type, {}).get(weekday.capitalize(), [])
        if lesson_index < len(lessons_today):
            current_subject = lessons_today[lesson_index]
            bot.send_message(
                message.chat.id,
                f"💼 Сейчас идёт {lesson_index + 1}-я пара: {current_subject}\n"
                f"Неделя: {week_type.capitalize()}.\n"
                f"Прошло времени: {elapsed_time} минут.\n"
                f"До окончания осталось: {remaining_time} минут."
            )
        else:
            bot.send_message(message.chat.id, "❌ Сегодня пар больше нет.")
    except FileNotFoundError:
        bot.send_message(message.chat.id, "❌ Тип недели не установлен. Обратитесь к Администратору.")
    except Exception as e:
        bot.send_message(message.chat.id, f"❌ Произошла ошибка: {str(e)}")


if __name__ == "__main__":
    run_bot()require 'lib.moonloader'
local imgui = require 'mimgui'
local sampev = require 'lib.samp.events'
local vkeys = require 'vkeys'
local encoding = require 'encoding'
local inicfg = require 'inicfg'
local ffi = require 'ffi'
local IniFilename = 'RepFlowCFG.ini'
local new = imgui.new
local faicons = require('fAwesome6')
local scriptver = "3.1 | Lite"

local changelogEntries = {
    { version = "2.6", description = "- Добавлено окно информации.\n- Исправлен баг с массовым спамом при сворачивании игры.\n- Исправлен баг с крашем игры при окне информации.\n- Добавлена новая вкладка 'ChangeLog'\n- Убрана вся лишняя информация с основного меню." },
    { version = "2.7", description = "- Изменен цвет сообщений скрипта.\n- Убран лишний спам при сворачивании игры.\n- Исправлен баг в информации версии 2.6.\n- Добавлена новая информация в окно информации\n- Изменена логика сворачивания игры." },
    { version = "2.8", description = "- Добавлен новый цвет меню.\n- Переименована вкладка 'Главная'.\nтеперь она называется флудер.\n- Добавлена функция отключить не флуди(сейчас нету репорта).\n- Мелкие исправления." },
    { version = "3.0", description = "- Ползунки теперь настраиваются!!.\n- Изменен код меню флудера и настроек.\n- Исправлено перемещение окна информации.\n- Заменена клавиша прикрепления окна на пробел.\n- Версия 2.9 и 3.0 объединены описанием" },
    { version = "3.1 | Lite", description = "- Новая тема - 'Светлая'.\n- Полностью переписана логика чата.\n- Было добавлено немного информации во вкладки.\n- Добавлены иконки в меню (fontAwesome6).\n- Добавлены новые индикаторы сообщений\n 'Информация' и 'RepFlow'.\n- Переписан код некоторых функций.\n- Разделение скрипта на Lite и Premium версию.\n- Улучшена оптимизация скрипта.\n- Мелкие исправления. " },
}

local keyBind = 0x5A -- клавиша активации: Z (по умолчанию)
local keyBindName = 'Z' -- Название клавиши активации

local lastDialogId = nil
local reportActive = false

local lastOtTime = 0 -- Время последней отправки /ot в секундах
local active = false
local otInterval = new.int(10) -- Интервал для автоматической отправки /ot
local dialogTimeout = new.int(600)
local otIntervalBuffer = imgui.new.char[5](tostring(otInterval[0])) -- Буфер на 5 символов (значения до 9999)
local useMilliseconds = new.bool(false) -- Флаг для использования миллисекунд
local infoWindowVisible = false -- Флаг для отображения окна информации
local reportAnsweredCount = 0 -- Счетчик для диалога 1334
local cursorVisible = false -- Для отслеживания видимости курсора

local main_window_state = new.bool(false)
local info_window_state = new.bool(false)
local active_tab = new.int(0)
local sw, sh = getScreenResolution()
local tag = "{1E90FF} [RepFlow]: {FFFFFF}"
local taginf = "{1E90FF} [Информация]: {FFFFFF}"

local startTime = 0 -- Время старта автоловли
local gameMinimized = false  -- Флаг для отслеживания сворачивания игры
local wasActiveBeforePause = false
local afkExitTime = 0  -- Время выхода из AFK
local afkCooldown = 30  -- Задержка в секундах перед началом ловли после выхода из AFK

local disableAutoStartOnToggle = false -- Флаг для отключения автостарта при ручном отключении ловли

local changingKey = false -- Флаг для отслеживания смены главной клавиши

encoding.default = 'CP1251'
u8 = encoding.UTF8

local dialogHandlerEnabled = true
local autoStartEnabled = true
local hideFloodMsg = new.bool(true)

--------- Актив и все, что с ним связано
local lastDialogTime = os.clock()
local dialogTimeoutBuffer = imgui.new.char[5](tostring(dialogTimeout[0])) -- Буфер на 5 символов (значения до 9999)
local manualDisable = false
local autoStartEnabled = new.bool(true)
local dialogHandlerEnabled = new.bool(true)
----------------------------------------

--[[local colorList = {u8'Красная', u8'Зелёная', u8'Синяя', u8'Оранжевая', u8'Серая', u8'Светлая'}
local colorListNumber = new.int(0)
local colorListBuffer = new['const char*'][#colorList](colorList)--]]
local active_tab = new.int(0)

-- Загрузка конфигурации
local ini = inicfg.load({
    main = {
        keyBind = string.format("0x%X", keyBind),
        keyBindName = keyBindName,
        otInterval = 10,
        useMilliseconds = false,
        themes = 1,
		dialogTimeout = 600,
		dialogHandlerEnabled = true,
        autoStartEnabled = true,
        otklflud = false,
    },
    widget = {
        posX = 400,
        posY = 400
    }
}, IniFilename)
local MoveWidget = false

-- Применение загруженной конфигурации
keyBind = tonumber(ini.main.keyBind)
keyBindName = ini.main.keyBindName
otInterval[0] = tonumber(ini.main.otInterval)
useMilliseconds[0] = ini.main.useMilliseconds
-- colorListNumber[0] = tonumber(ini.main.themes)
dialogTimeout[0] = tonumber(ini.main.dialogTimeout)
dialogHandlerEnabled[0] = ini.main.dialogHandlerEnabled
autoStartEnabled[0] = ini.main.autoStartEnabled or false
hideFloodMsg[0] = ini.main.otklflud

-- Основной цвет темы
local colors = {
    leftPanelColor = imgui.ImVec4(27 / 255, 20 / 255, 30 / 255, 1.0),        -- цвет левого прямоугольника
    rightPanelColor = imgui.ImVec4(24 / 255, 18 / 255, 28 / 255, 1.0),       -- цвет правого прямоугольника
    childPanelColor = imgui.ImVec4(18 / 255, 13 / 255, 22 / 255, 1.0),       -- цвет child-окна
    hoverColor = imgui.ImVec4(63 / 255, 59 / 255, 66 / 255, 1.0),            -- цвет наведения для кнопок
}

function drawThemeSelector()
    imgui.Text(u8"Выберите тему:")
    for i, theme in ipairs(themes) do
        local color = theme.previewColor or imgui.ImVec4(0.5, 0.5, 0.5, 1.0) -- Убедимся, что есть значение по умолчанию

        -- Добавляем ColorButton для выбора темы
        if imgui.ColorButton("##theme" .. i, color, imgui.ColorButtonFlags.NoTooltip + imgui.ColorButtonFlags.NoBorder, imgui.ImVec2(40, 40)) then
            theme.change() -- Применяем тему при клике на кнопку
            ini.main.themes = i - 1
            inicfg.save(ini, IniFilename)
        end

        -- Добавляем пробел между кнопками
        if i < #themes then
            imgui.SameLine()
        end
    end
end


function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end
    sampRegisterChatCommand("arep", cmd_arep)

    sampAddChatMessage(tag .. 'Скрипт {00FF00}загружен.{FFFFFF} Активация меню: {00FF00}/arep', -1)

    show_arz_notify('success', 'RepFlow', 'Успешная загрузка. Активация: /arep', 9000)

    while true do
        wait(0)

        checkPauseAndDisableAutoStart() -- Проверяем сворачивание игры
        checkAutoStart() -- Выполняется с задержкой, если игра не свернута

        imgui.Process = main_window_state[0] and not isGameMinimized

        -- Логика перемещения окна
        if MoveWidget then
            ini.widget.posX, ini.widget.posY = getCursorPos()
            local cursorX, cursorY = getCursorPos()
            ini.widget.posX = cursorX
            ini.widget.posY = cursorY
            if isKeyJustPressed(0x20) then -- Пробел для фиксации позиции
                MoveWidget = false
                sampToggleCursor(false)
                saveWindowSettings()
            end
        end

        -- Логика отображения окна информации
        if active or MoveWidget then
            showInfoWindow() -- Показываем окно информации только если ловля активна или идет перемещение
        else
            showInfoWindowOff() -- Скрываем окно, если ни одно условие не выполнено
        end

        -- Ловля активируется по клавише
        if not changingKey and isKeyJustPressed(keyBind) and not isSampfuncsConsoleActive() and not sampIsChatInputActive() and not sampIsDialogActive() and not isPauseMenuActive() then
            onToggleActive()
        end

        -- Если автоловля активна
        if active then
            local currentTime = os.clock() * 1000 -- Текущее время в миллисекундах

            -- Ловля репортов
            if useMilliseconds[0] then
                if currentTime - lastOtTime >= otInterval[0] then
                    sampSendChat('/ot')
                    lastOtTime = currentTime
                end
            else
                if (currentTime - lastOtTime) >= (otInterval[0] * 1000) then
                    sampSendChat('/ot')
                    lastOtTime = currentTime
                end
            end
        else
            -- Если автоловля неактивна, сбрасываем таймеры
            startTime = os.clock() -- Сбрасываем и фиксируем время начала автоловли
            attemptCount = 0 -- Сбрасываем количество попыток
        end
    end
end

function resetIO()
    for i = 0, 511 do
        imgui.GetIO().KeysDown[i] = false
    end
    for i = 0, 4 do
        imgui.GetIO().MouseDown[i] = false
    end
    imgui.GetIO().KeyCtrl = false
    imgui.GetIO().KeyShift = false
    imgui.GetIO().KeyAlt = false
    imgui.GetIO().KeySuper = false
end

function startMovingWindow()
    MoveWidget = true -- Включаем режим перемещения
    showInfoWindow() -- Показываем окно информации, чтобы пользователь мог его перемещать
    sampToggleCursor(true) -- Показываем курсор
    main_window_state[0] = false -- Закрываем основное окно
    sampAddChatMessage(taginf .. '{FFFF00}Режим перемещения окна активирован. Нажмите "Пробел" для подтверждения.', -1)
end

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    local config = imgui.ImFontConfig()
    config.MergeMode = true
    config.PixelSnapH = true
    iconRanges = imgui.new.ImWchar[3](faicons.min_range, faicons.max_range, 0)
    imgui.GetIO().Fonts:AddFontFromMemoryCompressedBase85TTF(faicons.get_font_data_base85('solid'), 14, config, iconRanges) -- solid - тип иконок, так же есть thin, regular, light и duotone
	--decor() -- применяем декор часть
    --themes[currentTheme[0]+1].change() -- применяем цветовую часть
end)

local dialogHandlerEnabled = new.bool(ini.main.dialogHandlerEnabled)

function decor()
    local ImVec4 = imgui.ImVec4
    imgui.SwitchContext()
    local style = imgui.GetStyle()
    style.WindowPadding = imgui.ImVec2(12, 12)
    style.WindowRounding = 8.0
    style.ChildRounding = 8.0
    style.FramePadding = imgui.ImVec2(6, 6)
    style.FrameRounding = 6.0
    style.ItemSpacing = imgui.ImVec2(8, 8)
    style.ItemInnerSpacing = imgui.ImVec2(6, 6)
    style.ScrollbarSize = 12.0
    style.ScrollbarRounding = 12.0
    style.GrabRounding = 8.0
    style.PopupRounding = 6.0
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
    style.ButtonTextAlign = imgui.ImVec2(0.5, 0.5)
end


function sampev.onServerMessage(color, text)
    if text:find('%[(%W+)%] от (%w+_%w+)%[(%d+)%]:') then
        if active then
            sampSendChat('/ot')
        end
    end
    return filterFloodMessage(text)
end

function onToggleActive()
    active = not active
    manualDisable = not active  -- Устанавливаем флаг для автостарта
    disableAutoStartOnToggle = not active -- Если ловля отключена вручную, отключаем автостарт

    local status = active and '{00FF00}включена' or '{FF0000}выключена'
    local statusArz = active and 'включена' or 'выключена'

    show_arz_notify('info', 'RepFlow', 'Ловля ' .. statusArz .. '!', 2000)
end

function saveWindowSettings()
    ini.widget.posX = ini.widget.posX or 400 -- Устанавливаем значение по умолчанию
    ini.widget.posY = ini.widget.posY or 400 -- Устанавливаем значение по умолчанию
    inicfg.save(ini, IniFilename) -- Сохраняем в INI-файл
    sampAddChatMessage(taginf .. '{00FF00}Положение окна сохранено!', -1)
end

function sampev.onShowDialog(dialogId, style, title, button1, button2, text)
    if dialogId == 1334 then
        lastDialogTime = os.clock() -- Сброс таймера при появлении диалога
        reportAnsweredCount = reportAnsweredCount + 1 -- Увеличиваем счетчик
        sampAddChatMessage(tag .. '{00FF00}Репорт принят! Отвечено репорта: ' .. reportAnsweredCount, -1)
        if active then
            active = false
            show_arz_notify('info', 'RepFlow', 'Ловля отключена из-за окна репорта!', 3000)
        end
    end
end

function checkAutoStart()
    local currentTime = os.clock()
    
    -- Проверяем, что ловля не активна, игра не свернута и прошло достаточно времени с выхода из AFK
    if autoStartEnabled[0] and not active and not gameMinimized and (afkExitTime == 0 or currentTime - afkExitTime >= afkCooldown) then
        -- Если отключение автостарта не было активировано вручную
        if not disableAutoStartOnToggle and (currentTime - lastDialogTime) > dialogTimeout[0] then
            active = true
            show_arz_notify('info', 'RepFlow', 'Ловля включена по таймауту', 3000)
        end
    end
end

function saveSettings()
    ini.main.dialogTimeout = dialogTimeout[0]
    inicfg.save(ini, IniFilename)
end

function imgui.Link(link, text)
	text = text or link
	local tSize = imgui.CalcTextSize(text)
	local p = imgui.GetCursorScreenPos()
	local DL = imgui.GetWindowDrawList()
	local col = { 0xFFFF7700, 0xFFFF9900 }
	if imgui.InvisibleButton('##' .. link, tSize) then os.execute('explorer ' .. link) end
	local color = imgui.IsItemHovered() and col[1] or col[2]
	DL:AddText(p, color, text)
	DL:AddLine(imgui.ImVec2(p.x, p.y + tSize.y), imgui.ImVec2(p.x + tSize.x, p.y + tSize.y), color)
end

function cmd_arep(arg)
    main_window_state[0] = not main_window_state[0]
    imgui.Process = main_window_state[0]
end

function drawMainTab()
    -- Отображение заголовка
    imgui.CenterText(u8"Настройки флудера")
    imgui.Separator()

    imgui.PushItemWidth(100)

    -- Чекбокс для использования миллисекунд
    if imgui.Checkbox(u8'Использовать миллисекунды', useMilliseconds) then
        ini.main.useMilliseconds = useMilliseconds[0]
        inicfg.save(ini, IniFilename)
    end

    imgui.PopItemWidth()

    -- Текстовое поле для интервала отправки команды /ot
    imgui.Text(u8'Интервал отправки команды /ot (' .. (useMilliseconds[0] and u8'в миллисекундах' or u8'в секундах') .. '):')

    -- Текущее значение интервала
    imgui.Text(u8'Текущий интервал: ' .. otInterval[0] .. (useMilliseconds[0] and u8' мс' or u8' секунд'))

    imgui.PushItemWidth(45)

    -- Поле для ввода интервала
    imgui.InputText(u8'##otIntervalInput', otIntervalBuffer, ffi.sizeof(otIntervalBuffer))
    imgui.SameLine()
    -- Кнопка для сохранения интервала
    if imgui.Button(faicons('floppy_disk') .. u8" Сохранить интервал") then
        local newValue = tonumber(ffi.string(otIntervalBuffer)) -- Преобразуем строку в число
        if newValue ~= nil then
            otInterval[0] = newValue -- Обновляем значение otInterval
            ini.main.otInterval = otInterval[0] -- Сохраняем в конфиг
            inicfg.save(ini, IniFilename)
            sampAddChatMessage(taginf .. "Интервал сохранён: {32CD32}" .. newValue .. (useMilliseconds[0] and " мс" or " секунд"), -1)
        else
            sampAddChatMessage(taginf .. "Некорректное значение. {32CD32}Введите число.", -1)
        end
    end

    imgui.PopItemWidth()

    imgui.Separator()

    -- Информационные сообщения
    imgui.Text(u8'Скрипт также ищет надпись в чате [Репорт] от Имя_Фамилия.')
    imgui.Text(u8'Флудер нужен для дополнительного способа ловли репорта.')

    imgui.Separator()
end

function drawSettingsTab()
    -- Заголовок с иконками для вкладки
    imgui.Text(faicons('gear') .. u8" Настройки  /  " .. faicons('sliders') .. u8" Основные настройки")
    imgui.Separator()

    -- Создаем блок настройки клавиши активации
    imgui.BeginChild("ActivationKey", imgui.ImVec2(0, 60), true)
    imgui.Text(u8'Текущая клавиша активации:')
    imgui.SameLine()
    if imgui.Button(u8'' .. keyBindName) then
        changingKey = true
        show_arz_notify('info', 'RepFlow', 'Нажмите новую клавишу для активации', 2000)
    end
    imgui.EndChild()
    imgui.Separator()

    -- Блок выбора темы
    imgui.BeginChild("ThemeSelector", imgui.ImVec2(0, 120), true)
    imgui.Text(u8'Выберите тему:')
    drawThemeSelector() -- Селектор тем через квадратики
    imgui.EndChild()
    imgui.Separator()

    -- Блок обработки диалогов
    imgui.BeginChild("DialogOptions", imgui.ImVec2(0, 100), true)
    imgui.Text(u8"Обработка диалогов")
    if imgui.Checkbox(u8'Обрабатывать диалоги', dialogHandlerEnabled) then
        ini.main.dialogHandlerEnabled = dialogHandlerEnabled[0]
        inicfg.save(ini, IniFilename)
    end
    if imgui.Checkbox(u8'Автостарт ловли по большому активу', autoStartEnabled) then
        ini.main.autoStartEnabled = autoStartEnabled[0]
        inicfg.save(ini, IniFilename)
    end
    if imgui.Checkbox(u8'Отключить сообщение "Не флуди"', hideFloodMsg) then
        ini.main.otklflud = hideFloodMsg[0]
        inicfg.save(ini, IniFilename)
    end
    imgui.EndChild()
    imgui.Separator()

    -- Блок ввода тайм-аута для автостарта
    imgui.BeginChild("AutoStartTimeout", imgui.ImVec2(0, 100), true)
    imgui.Text(u8'Настройка тайм-аута автостарта')
    imgui.PushItemWidth(45)
    imgui.Text(u8'Текущий тайм-аут: ' .. dialogTimeout[0] .. u8' секунд')
    imgui.InputText(u8'', dialogTimeoutBuffer, ffi.sizeof(dialogTimeoutBuffer))
    imgui.SameLine()
    if imgui.Button(faicons('floppy_disk') .. u8" Сохранить тайм-аут") then
        local newValue = tonumber(ffi.string(dialogTimeoutBuffer))
        if newValue ~= nil and newValue >= 1 and newValue <= 9999 then
            dialogTimeout[0] = newValue -- Обновляем тайм-аут
            saveSettings() -- Сохраняем изменения
            sampAddChatMessage(taginf .. "Тайм-аут сохранён: {32CD32}" .. newValue .. " секунд", -1)
        else
            sampAddChatMessage(taginf .. "Некорректное значение. {32CD32}Введите от 1 до 9999.", -1)
        end
    end
    imgui.PopItemWidth()
    imgui.EndChild()
    imgui.Separator()

    -- Блок изменения положения окна
    imgui.BeginChild("WindowPosition", imgui.ImVec2(0, 50), true)
    imgui.Text(u8'Положение окна информации:')
    imgui.SameLine()
    if imgui.Button(u8'Изменить положение') then
        startMovingWindow() -- Активируем перемещение окна при нажатии
    end
    imgui.EndChild()
end

function saveColorCode()
    ini.main.colorCode = ffi.string(colorCode)
    inicfg.save(ini, IniFilename)
end

function filterFloodMessage(text)
    if hideFloodMsg[0] and text:find("%[Ошибка%] {FFFFFF}Сейчас нет вопросов в репорт!") then
        return false -- Блокируем сообщение "Не флуди"
    end
end

-- Функция для проверки сворачивания игры и отключения автостарта
function checkPauseAndDisableAutoStart()
    if isPauseMenuActive() then
        -- Игра свернута
        if not gameMinimized then
            -- Сохраняем состояние ловли перед сворачиванием
            wasActiveBeforePause = active

            -- Отключаем автоловлю, если она была активна
            if active then
                active = false -- Отключаем ловлю
            end

            -- Ставим флаг, что игра свернута
            gameMinimized = true
        end
    else
        -- Игра развернута
        if gameMinimized then
            -- Если игра была свернута и ловля была активна, можно снова её включить или вывести сообщение
            gameMinimized = false

            -- Если ловля была активна перед сворачиванием, возможно, можно активировать её через таймер
            if wasActiveBeforePause then
                sampAddChatMessage(tag .. '{FFFFFF}Вы вышли из паузы. Ловля отключена из-за AFK!!', -1)
            end
        end
    end
end

function drawInfoTab()
    imgui.CenterText(u8'Информация о скрипте')
    imgui.Separator()
    imgui.Text(u8'Автор: Matthew_McLaren[18]')
    imgui.Text(u8'Версия: %s', scriptver)
	imgui.Text(u8'Связь с разработчиком:')
	imgui.SameLine()
	imgui.Link('https://t.me/Zorahm', 'Telegram')
    imgui.Text(u8'')
    imgui.Text(u8'Скрипт автоматически отправляет команду /ot.')
    imgui.Text(u8'Через определенные интервалы времени.')
    imgui.Text(u8'А также выслеживает определенные надписи.')
	imgui.Text(u8'')
    imgui.CenterText(u8'А также спасибо:')
    imgui.Text(u8'Тестер: Carl_Mort[18].')
end

-- Функция для отрисовки вкладки "ChangeLog"
function drawChangeLogTab()
    imgui.CenterText(u8("Изменения по версиям:"))
    imgui.Separator()

    -- Проходим по каждому элементу в changelog
    for _, entry in ipairs(changelogEntries) do
        if imgui.CollapsingHeader(u8("Версия ") .. entry.version) then
            -- Если заголовок раскрыт, отображаем описание изменений
            imgui.Text(u8(entry.description)) -- Указываем кодировку UTF-8 для отображения русского текста
        end
    end
end

imgui.OnFrame(function() return main_window_state[0] end, function(player)
    imgui.SetNextWindowSize(imgui.ImVec2(600, 400), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.PushStyleColor(imgui.Col.WindowBg, colors.rightPanelColor)
    imgui.Begin(u8'Настройки', main_window_state, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse)
    
    -- Левый панель с вкладками
    imgui.BeginChild("left_panel", imgui.ImVec2(150, 0), true, imgui.WindowFlags.NoScrollbar)
    imgui.PushStyleColor(imgui.Col.ChildBg, colors.leftPanelColor)
    -- imgui.PushStyleVar(imgui.StyleVar.ChildRounding, 5)
    
    -- Оформление кнопок для вкладок
    local tabNames = { "Оформление", "Настройки", "Информация" }
    for i, name in ipairs(tabNames) do
        if i - 1 == active_tab[0] then
            imgui.PushStyleColor(imgui.Col.Button, colors.hoverColor)
        else
            imgui.PushStyleColor(imgui.Col.Button, colors.leftPanelColor)
        end
        imgui.PushStyleColor(imgui.Col.ButtonHovered, colors.hoverColor)
        imgui.PushStyleColor(imgui.Col.ButtonActive, colors.hoverColor)
        
        if imgui.Button(u8(name), imgui.ImVec2(125, 40)) then
            active_tab[0] = i - 1
        end
        imgui.PopStyleColor(3)
    end
    
    imgui.PopStyleColor()
    imgui.PopStyleVar()
    imgui.EndChild()

    imgui.SameLine()

    -- Панель для содержимого вкладок
    imgui.BeginChild("right_panel", imgui.ImVec2(0, 0), true)
    imgui.PushStyleColor(imgui.Col.ChildBg, colors.childPanelColor)
    -- imgui.PushStyleVar(imgui.StyleVar.ChildRounding, 10)

    if active_tab[0] == 0 then
        drawThemeTab()
    elseif active_tab[0] == 1 then
        drawSettingsTab()
    elseif active_tab[0] == 2 then
        drawInfoTab()
    end

    imgui.PopStyleColor()
    imgui.PopStyleVar()
    imgui.EndChild()

    imgui.End()
    imgui.PopStyleColor()
end)

function onWindowMessage(msg, wparam, lparam)
    if changingKey then
        if msg == 0x100 or msg == 0x101 then -- WM_KEYDOWN or WM_KEYUP
            keyBind = wparam
            keyBindName = vkeys.id_to_name(keyBind) -- Вызов функции для получения имени клавиши
            changingKey = false
            ini.main.keyBind = string.format("0x%X", keyBind)
            ini.main.keyBindName = keyBindName
            inicfg.save(ini, IniFilename)
            sampAddChatMessage(string.format(tag .. '{FFFFFF}Новая клавиша активации ловли репорта: {00FF00}%s', keyBindName), -1)
            return false -- предотвращает дальнейшую обработку сообщения
        end
    end
end

function imgui.CenterText(text)
    local width = imgui.GetWindowWidth()
    local calc = imgui.CalcTextSize(text)
    imgui.SetCursorPosX(width / 2 - calc.x / 2)
    imgui.Text(text)
end

-- Аризоновские уведомления
function show_arz_notify(type, title, text, time)
    if MONET_VERSION ~= nil then
        if type == 'info' then
            type = 3
        elseif type == 'error' then
            type = 2
        elseif type == 'success' then
            type = 1
        end
        local bs = raknetNewBitStream()
        raknetBitStreamWriteInt8(bs, 62)
        raknetBitStreamWriteInt8(bs, 6)
        raknetBitStreamWriteBool(bs, true)
        raknetEmulPacketReceiveBitStream(220, bs)
        raknetDeleteBitStream(bs)
        local json = encodeJson({
            styleInt = type,
            title = title,
            text = text,
            duration = time
        })
        local interfaceid = 6
        local subid = 0
        local bs = raknetNewBitStream()
        raknetBitStreamWriteInt8(bs, 84)
        raknetBitStreamWriteInt8(bs, interfaceid)
        raknetBitStreamWriteInt8(bs, subid)
        raknetBitStreamWriteInt32(bs, #json)
        raknetBitStreamWriteString(bs, json)
        raknetEmulPacketReceiveBitStream(220, bs)
        raknetDeleteBitStream(bs)
    else
        local str = ('window.executeEvent(\'event.notify.initialize\', \'["%s", "%s", "%s", "%s"]\');'):format(type, title, text, time)
        local bs = raknetNewBitStream()
        raknetBitStreamWriteInt8(bs, 17)
        raknetBitStreamWriteInt32(bs, 0)
        raknetBitStreamWriteInt32(bs, #str)
        raknetBitStreamWriteString(bs, str)
        raknetEmulPacketReceiveBitStream(220, bs)
        raknetDeleteBitStream(bs)
    end
end

-- Функция для отрисовки окна информации
imgui.OnFrame(function() return info_window_state[0] end, function(self)
    self.HideCursor = true
    -- Устанавливаем минимальные и максимальные размеры окна
    imgui.SetNextWindowSize(imgui.ImVec2(220, 175), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowPos(imgui.ImVec2(ini.widget.posX, ini.widget.posY), imgui.Cond.Always)

    -- Начало окна с флагами
    imgui.Begin(faicons('gear') .. u8" Информация " .. faicons('gear'), info_window_state, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse)
    imgui.CenterText(u8'Статус Ловли: Включена')
    -- Время работы автоловли
    local elapsedTime = os.clock() - startTime
    imgui.CenterText(string.format(u8'Время работы: %.2f сек', elapsedTime))

    -- Количество ответов на репорт (появление диалога 1334)
    imgui.CenterText(string.format(u8'Отвечено репорта: %d', reportAnsweredCount))
    imgui.Separator()
    -- Статус обработки диалогов
    imgui.Text(u8'Обработка диалогов:')
    imgui.SameLine()
    if dialogHandlerEnabled[0] then
        imgui.Text(u8'Включена')
    else
        imgui.Text(u8'Выкл.')
    end

    -- Статус автостарта
    imgui.Text(u8'Автостарт:')
    imgui.SameLine()
    if autoStartEnabled[0] then
        imgui.Text(u8'Включен')
    else
        imgui.Text(u8'Выключен')
    end
    imgui.End() -- Завершение окна
end)

-- Пример функции для активации окна информации
function showInfoWindow()
    info_window_state[0] = true
end

function showInfoWindowOff()
    info_window_state[0] = false
end
