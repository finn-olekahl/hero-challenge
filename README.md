# HERO AI Mode

This project was written for the Future Leader Summit AI Hackathon 2026 in Hamburg by T. Urbutt, M. Wannags, and F. Kahl.

Hackathon: https://chef-treff.de/en/hackathon/

## Overview

HERO AI Mode is a native iOS prototype for the HERO craftsman app. Its goal is to simplify offer creation on site: the user speaks, takes photos, and captures measurements, and the app turns that recording into a structured offer flow.

The core idea is timestamp-based context binding. Speech, photos, and measurements are recorded on a shared timeline so the AI can understand not only what was captured, but also what it belongs to.

## Recording Flow

1. Start recording: the camera opens and speech recognition starts automatically.
2. Capture context: the user can take photos, perform AR measurements, or pause during the recording.
3. Stop recording: the timeline containing transcript, photos, and measurements is sent to the AI pipeline.
4. AI evaluation: the system identifies services, material categories, project context, and open questions.
5. Questionnaire: missing details are resolved before document creation.
6. Offer creation: the final offer is created through the HERO GraphQL API.

The same recording flow is intended to support work reports and site reports later on.

## Questionnaire Types

1. Project request: always the first question, prefilled when possible and editable.
2. Billing questions: per service, clarify hours and quantity or select a service type.
3. Article questions: per identified material, select a concrete product from the HERO catalog.
4. Free text questions: for all remaining missing information.

## Tech Stack

- Swift with a native iOS app architecture
- ARKit, RealityKit, and AVFoundation for camera and measurement features
- Apple Speech Framework for speech recognition
- HERO GraphQL API for account-linked project and document creation
- OpenAI models for evaluation and generation

## Project Structure

- `hero-challenge/App`: app entry points and top-level UI
- `hero-challenge/Core`: models, networking, and shared services
- `hero-challenge/Features`: feature-specific controllers, models, and views
- `hero-challenge/Resources`: asset catalog and app resources

## Setup

### Requirements

- macOS
- Xcode 26 or newer recommended
- iOS Simulator or a physical iPhone
- Access to HERO API credentials
- An OpenAI API key

### Environment

Create a `.env` file in the project root with the following values:

```env
OPENAI_API_KEY=your_openai_key
MAIN_MODEL=gpt-4.1-mini
HERO_API_TOKEN=your_hero_token
HERO_API_URL=https://login.hero-software.de/api/external/v9/graphql
```

Notes:

- `MAIN_MODEL` defaults to `gpt-4.1-mini` if omitted.
- `HERO_API_URL` is normalized to the HERO v9 GraphQL endpoint.

## Run Locally

1. Open `hero-challenge.xcodeproj` in Xcode.
2. Select the `hero-challenge` scheme.
3. Choose an iOS Simulator or connected device.
4. Build and run the app.

You can also build from the command line:

```bash
xcodebuild -project hero-challenge.xcodeproj -scheme hero-challenge -configuration Debug
```

## Status

This repository is a hackathon prototype focused on the end-to-end recording, AI evaluation, questionnaire, and offer generation workflow.

Planned extensions include:

- work reports
- site reports
- offline-first recording
- learning from questionnaire corrections over time