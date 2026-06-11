# Deep Seek Pitch Presentation Prompts

Use these prompts with Deep Seek to generate HTML presentation slides.

---

## Prompt 1: Full Presentation

```
Create a professional HTML presentation for a mobile app pitch using reveal.js.

App Name: DSLS (Dynamic Speed Limit System)
Tagline: Intelligent Speed Recommendations & Driving Safety

Key Features:
- Dynamic speed limit recommendations based on road type, weather, time
- Real-time driving safety alerts and scoring
- Driver behavior analytics with charts
- Camera integration for road sign recognition
- GPS-based zone monitoring
- Vibration and audio alerts
- Trip history tracking

Tech Stack: Flutter (Dart), Provider state management, Google Maps (flutter_map), SQLite, multiple sensors

Design: Modern, clean, dark mode capable, gradient accents (#5B4B8A to #7B68EE)

Create a 10-slide presentation:
1. Title slide with app logo placeholder
2. Problem statement - why drivers need this
3. Solution overview
4. Key features (3-4 slides)
5. Technology stack
6. Demo screenshots placeholders
7. Market potential
8. Team/roadmap
9. Call to action
10. Contact slide

Use reveal.js with a dark theme. Include smooth transitions, progress bar, and keyboard navigation. Make it visually striking with CSS gradients and animations.
```

---

## Prompt 2: Features Deep Dive

```
Create an HTML slide deck focusing on features using reveal.js.

App: DSLS - Dynamic Speed Limit System

Features to highlight:
1. Dynamic Speed Recommendations - AI-powered suggestions based on road type, weather conditions, time of day, traffic
2. Safety Alerts - Real-time warnings for speeding, harsh braking, lane departure
3. Driver Score - Comprehensive scoring system (0-100) based on acceleration, braking, cornering, speed compliance
4. Zone Monitoring - GPS-based alerts for school zones, construction zones, speed cameras
5. Camera Integration - Capture and analyze road signs
6. Analytics Dashboard - Charts showing trends over time (fl_chart)
7. Trip History - Record and review past trips
8. Voice & Vibration Alerts - Multi-modal notification system

Create 8 slides with icons, brief descriptions, and visual mockup placeholders. Use reveal.js with 'black' theme and purple accent colors (#7B68EE). Add fragment transitions for bullet points.
```

---

## Prompt 3: Technical Overview

```
Generate HTML slides using reveal.js for a technical pitch.

Project: DSLS App (Flutter)
Target Platforms: Android (iOS future)

Architecture:
- Clean Architecture with separation of concerns
- Provider for state management
- Repository pattern for data access

Key Dependencies:
- geolocator, flutter_map, latlong2 - GPS/Maps
- fl_chart - Data visualization
- camera, image_picker - Camera integration
- sensors_plus - Device sensors
- audioplayers, flutter_tts - Audio feedback
- vibration - Haptic feedback
- permission_handler - Runtime permissions
- shared_preferences - Local storage
- encrypt - Data security
- uuid - Unique identifiers

Features:
- Real-time location tracking with background processing
- Custom map overlays for speed zones
- Real-time chart updates
- Multi-permission handling (camera, location, storage)
- TTS voice announcements

Create 6 slides: Architecture diagram placeholder, tech stack grid, key features as icons, data flow visualization placeholder, security features, scalability. Use code-style formatting for technical details.
```

---

## Prompt 4: Quick One-Pager

```
Create a single-page HTML presentation using reveal.js.

App: DSLS - Dynamic Speed Limit System
Type: Mobile app pitch deck

Slides:
1. DSLS - Dynamic Speed Limit System (logo, tagline)
2. The Problem - Speeding causes 30% of traffic deaths
3. Our Solution - AI-powered real-time speed recommendations
4. Key Features (grid of 4-6 features with emojis)
5. Driver Score Demo (placeholder for chart)
6. Tech Stack: Flutter + Maps + Sensors
7. Market Opportunity - $X billion
8. Contact - Name, Email, Phone

Use reveal.js with smooth slide transitions, dark theme (#1a1a2e background), purple/gold accent colors. Include sample placeholder images. Make it mobile-responsive.
```