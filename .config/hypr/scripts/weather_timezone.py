#!/usr/bin/env python

"""
weather_timezone.py

Fetches weather data and local date/time for a list of cities from OpenWeatherMap.
Cycles through cities when called with the argument "next".
Outputs a JSON object with keys "text" and "tooltip" that Waybar uses.

Usage:
  - To display the current city's info: run the script normally.
  - To cycle to the next city: run the script with the argument "next".
  
A state file (/tmp/current_city_index.txt) is used to persist the current city index.
Weather data is cached in /tmp/weather_cache.json to avoid excessive API requests.
"""

import requests
import json
import sys
from datetime import datetime
import pytz
import os
import pycountry
import time

# --- Configuration for Text Case ---
# Set to True for UPPERCASE output, False for regular text
UPPERCASE_OUTPUT = True 
# --- End Configuration ---

# OpenWeatherMap API Key
API_KEY = "02a821687721a64a16cf83990f2ff186" 

# List of cities to cycle through.
# Each tuple is: (Display Name, Query for OWM, Timezone)
CITIES = [
    ('La Paz', 'La Paz,BO', 'America/La_Paz'),
    ('Amsterdam', 'Amsterdam,NL', 'Europe/Amsterdam'),
    ('Helsinki', 'Helsinki,FI', 'Europe/Helsinki'),
    ('Tokyo', 'Tokyo,JP', 'Asia/Tokyo'),
]

# File to store the current city index persistently
STATE_FILE = '/tmp/current_city_index.txt'
WEATHER_CACHE_FILE = '/tmp/weather_cache.json'

def read_index():
    try:
        with open(STATE_FILE, 'r') as f:
            idx = int(f.read().strip())
            if 0 <= idx < len(CITIES):
                return idx
    except Exception:
        pass
    return 0

def write_index(idx):
    with open(STATE_FILE, 'w') as f:
        f.write(str(idx))

def should_update_weather():
    """ Checks if we should update the weather data (only every 5 minutes). """
    try:
        if os.path.exists(WEATHER_CACHE_FILE):
            with open(WEATHER_CACHE_FILE, 'r') as f:
                cache = json.load(f)
                last_update = datetime.fromisoformat(cache.get('last_update'))
                if (datetime.now() - last_update).total_seconds() < 300:
                    return False, cache
    except Exception:
        pass
    return True, None

def save_weather_cache(data):
    """ Saves weather data to the cache file. """
    cache = {'last_update': datetime.now().isoformat(), 'weather': data}
    with open(WEATHER_CACHE_FILE, 'w') as f:
        json.dump(cache, f)

def get_weather_data(query):
    """ Fetches weather data from OpenWeatherMap with retry mechanism. """
    url = f'http://api.openweathermap.org/data/2.5/weather?q={query}&appid={API_KEY}&units=metric&lang=en'
    attempt = 0
    max_attempts = 10
    while attempt < max_attempts:
        try:
            response = requests.get(url, timeout=2)
            response.raise_for_status()
            return response.json(), None
        except requests.exceptions.RequestException as req_err:
            attempt += 1
            if attempt < max_attempts:
                time.sleep(5)  # Wait for 5 seconds before retrying
            else:
                return None, f"Request failed after {max_attempts} attempts: {req_err}"
    return None, "Request failed: unknown error"

# Read the current city index.
current_index = read_index()

# If the script is called with the argument 'next', cycle to the next city.
if len(sys.argv) > 1 and sys.argv[1] == 'next':
    current_index = (current_index + 1) % len(CITIES)
    write_index(current_index)

# Get the current city's details.
city_name, city_query, city_tz = CITIES[current_index]

# --- Prepare text components, applying uppercase if needed ---
display_city_name = city_name

# Get the local date and time for the city's timezone.
tz = pytz.timezone(city_tz)
local_dt = datetime.now(tz)

# Extract date/time components for conditional uppercasing
display_date_time_parts = {
    'day_of_week': local_dt.strftime("%A"),
    'month_day': local_dt.strftime("%B %-d"),
    'hour_minute_ampm': local_dt.strftime("%-I:%M %p")
}

# Apply uppercase transformation to these display variables if UPPERCASE_OUTPUT is True
if UPPERCASE_OUTPUT:
    display_city_name = city_name.upper() # Ensures consistency even if pre-uppercased in CITIES
    for key in display_date_time_parts:
        display_date_time_parts[key] = display_date_time_parts[key].upper()

# Reconstruct the date_time_string using the (potentially uppercased) parts
# This ensures Pango tags are not touched by .upper()
date_time_string_formatted = (
    f"{display_date_time_parts['day_of_week']}, "
    f"{display_date_time_parts['month_day']}<span foreground='#cdd6f466'>    </span>"
    f"{display_date_time_parts['hour_minute_ampm']}"
)

# Check if we should update weather data or use cached data
update_weather, cached_data = should_update_weather()

if update_weather:
    weather_data, error_message = get_weather_data(city_query)
    if weather_data:
        save_weather_cache(weather_data)
else:
    weather_data = cached_data['weather']

if weather_data is None:
    # Log the error
    with open("/tmp/weather_error.log", "a") as f:
        f.write(f"{datetime.now()}: {error_message}\n")

    # Define error labels and apply uppercase if needed
    error_text_label = "Weather Error (!)"
    local_time_label = "Local time"
    could_not_fetch_label = "Could not fetch weather data:"

    if UPPERCASE_OUTPUT:
        error_text_label = error_text_label.upper()
        local_time_label = local_time_label.upper()
        could_not_fetch_label = could_not_fetch_label.upper()

    waybar_text = f"<span foreground='#cfd9f5'>{display_city_name}</span><span foreground='#cdd6f466'>    </span>{date_time_string_formatted}<span foreground='#cdd6f466'>    </span>{error_text_label}"
    waybar_tooltip = (
        f"<span foreground='#cfd9f5'>{display_city_name}</span>\n\n"
        f"{local_time_label}: {date_time_string_formatted}\n\n"
        f"{could_not_fetch_label}\n{error_message}" # error_message itself is not uppercased
    )
else:
    # Extract weather details safely
    country_code = weather_data.get('sys', {}).get('country')
    country = pycountry.countries.get(alpha_2=country_code).name if pycountry.countries.get(alpha_2=country_code) else country_code

    temperature = round(weather_data['main']['temp'])
    feels_like = round(weather_data['main']['feels_like'])
    weather_desc = weather_data['weather'][0]['description'].capitalize()
    humidity = weather_data['main']['humidity']
    pressure = weather_data['main']['pressure']
    wind_speed = round(weather_data['wind']['speed'], 1)
    visibility = round(weather_data.get('visibility', 10000) / 1000)  # Convert meters to km
    cloudiness = weather_data['clouds']['all']  # Cloud coverage in %
    rain = weather_data.get('rain', {}).get('1h', 0)  # Rain volume in mm
    snow = weather_data.get('snow', {}).get('1h', 0)  # Snow volume in mm

    # Apply uppercase to weather_desc if needed
    display_weather_desc = weather_desc
    if UPPERCASE_OUTPUT:
        display_weather_desc = weather_desc.upper()

    # Format the output for Waybar's text (concise version)
    waybar_text = f"{display_city_name}<span foreground='#cdd6f466'>    </span>{temperature}°C  {display_weather_desc}<span foreground='#cdd6f466'>    </span>{date_time_string_formatted}"

    # Detailed weather info for tooltip
    # Define labels that need uppercasing for the tooltip
    tooltip_labels = {
        "Temperature": "Temperature",
        "Feels like": "Feels like",
        "Condition": "Condition",
        "Humidity": "Humidity",
        "Pressure": "Pressure",
        "Cloudiness": "Cloudiness",
        "Wind": "Wind",
        "Visibility": "Visibility",
        "Rain": "Rain",
        "Snow": "Snow"
    }

    if UPPERCASE_OUTPUT:
        for key in tooltip_labels:
            tooltip_labels[key] = tooltip_labels[key].upper()

    waybar_tooltip = (
        f"<span foreground='#CDD6F4' size='14pt'>{display_city_name}</span>\n\n"
        f"{date_time_string_formatted}\n\n"
        f"{tooltip_labels['Temperature']}: {temperature}°C\n"
        f"{tooltip_labels['Feels like']}: {feels_like}°C\n"
        f"{tooltip_labels['Condition']}: {display_weather_desc}\n"
        f"{tooltip_labels['Humidity']}: {humidity}%\n"
        f"{tooltip_labels['Pressure']}: {pressure} hPa\n"
        f"{tooltip_labels['Cloudiness']}: {cloudiness}%\n"
        f"{tooltip_labels['Wind']}: {wind_speed} m/s\n"
        f"{tooltip_labels['Visibility']}: {visibility} km\n"
        f"{tooltip_labels['Rain']}: {rain} mm\n"
        f"{tooltip_labels['Snow']}: {snow} mm"
    )

# Final JSON output for Waybar
result = {"text": waybar_text, "tooltip": waybar_tooltip}

# Print the JSON output for Waybar.
print(json.dumps(result, ensure_ascii=False))