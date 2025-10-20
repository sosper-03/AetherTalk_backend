# 🌍 AetherTalk Streaming Translation System

## Overview

AetherTalk now features a comprehensive real-time streaming translation system that breaks down language barriers during conversations. The system provides a complete Audio → STT → Translation → TTS pipeline with user-controlled opt-in preferences.

## 🎯 Key Features

### ✅ Complete Translation Pipeline
- **Real-time Audio Processing**: Stream audio chunks for immediate processing
- **Speech-to-Text (STT)**: Convert spoken words to text using Maestra API
- **Text Translation**: Translate text between languages using Lecto AI
- **Text-to-Speech (TTS)**: Convert translated text back to speech using NoteGPT
- **Streaming Architecture**: Process audio in real-time without delays

### ✅ Service Integrations

#### 🔤 Lecto AI Translation Service
- **API Key**: `JAKBSJP-A2WMV50-N43CNV1-2F8X8EV`
- **Features**: Real-time text translation between 125+ languages
- **Streaming Support**: Process text chunks as they arrive
- **Language Detection**: Automatic source language detection
- **Module**: `aethertalk_lecto_ai.erl`

#### 🎤 Maestra Speech-to-Text Service
- **Features**: Convert speech to text in 125+ languages
- **Streaming Support**: Process audio chunks in real-time
- **Format Support**: WAV, MP3, M4A, FLAC, OGG
- **Module**: `aethertalk_maestra_stt.erl`

#### 🔊 NoteGPT Text-to-Speech Service
- **Features**: Convert text to speech with 100+ voices
- **Voice Options**: Multiple male/female voices per language
- **Streaming Support**: Generate audio chunks as text arrives
- **Quality**: High-quality speech synthesis
- **Module**: `aethertalk_notegpt_tts.erl`

### ✅ User Control System

#### Translation Settings
Users have complete control over their translation experience:

```json
{
  "enabled": true,              // Enable/disable translation
  "source_language": "auto",    // Auto-detect or specific language
  "target_language": "es",      // Target translation language
  "voice": "es-ES-female-1",    // Preferred voice for TTS
  "text_output": true,          // Show translated text
  "voice_output": true,         // Play translated audio
  "auto_detect": true           // Auto-detect source language
}
```

#### Opt-in System
- Translation is **disabled by default**
- Users must explicitly enable translation
- Granular control over text vs. voice output
- Per-user settings persistence in database

## 🏗️ Architecture

### Core Components

1. **Streaming Translation Coordinator** (`aethertalk_streaming_translation.erl`)
   - Orchestrates the complete pipeline
   - Manages user sessions and preferences
   - Coordinates between STT, Translation, and TTS services

2. **Service Modules**
   - `aethertalk_lecto_ai.erl` - Text translation
   - `aethertalk_maestra_stt.erl` - Speech-to-text
   - `aethertalk_notegpt_tts.erl` - Text-to-speech

3. **API Layer** (`aethertalk_streaming_translation_api.erl`)
   - REST endpoints for translation management
   - User settings management
   - Direct translation services

4. **WebSocket Handler** (`aethertalk_streaming_translation_ws.erl`)
   - Real-time translation events
   - Streaming audio/text processing
   - Live translation updates

### Database Schema

```sql
-- User translation settings table
CREATE TABLE user_translation_settings (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    enabled BOOLEAN DEFAULT FALSE,
    source_language VARCHAR(10) DEFAULT 'auto',
    target_language VARCHAR(10) DEFAULT 'en',
    voice VARCHAR(50) DEFAULT 'en-US-female-1',
    text_output BOOLEAN DEFAULT TRUE,
    voice_output BOOLEAN DEFAULT TRUE,
    auto_detect BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

## 🔌 API Endpoints

### Translation Management

#### Start Streaming Translation
```http
POST /api/v1/translation/streaming/start
Authorization: Bearer <jwt_token>
Content-Type: application/json

{
  "source_language": "en",
  "target_language": "es",
  "voice": "es-ES-female-1"
}
```

#### Stream Audio Data
```http
POST /api/v1/translation/streaming/{session_id}/audio
Authorization: Bearer <jwt_token>
Content-Type: application/octet-stream

<binary audio data>
```

#### End Streaming Session
```http
POST /api/v1/translation/streaming/{session_id}/end
Authorization: Bearer <jwt_token>
```

### User Settings

#### Get Translation Settings
```http
GET /api/v1/translation/settings
Authorization: Bearer <jwt_token>
```

#### Update Translation Settings
```http
PUT /api/v1/translation/settings
Authorization: Bearer <jwt_token>
Content-Type: application/json

{
  "enabled": true,
  "source_language": "auto",
  "target_language": "fr",
  "voice": "fr-FR-female-1",
  "text_output": true,
  "voice_output": true
}
```

### Information Endpoints

#### Get Supported Languages
```http
GET /api/v1/translation/languages
```

#### Get Available Voices
```http
GET /api/v1/translation/voices
```

#### Direct Text Translation
```http
POST /api/v1/translation/text
Authorization: Bearer <jwt_token>
Content-Type: application/json

{
  "text": "Hello, how are you?",
  "source_language": "en",
  "target_language": "es"
}
```

#### Language Detection
```http
POST /api/v1/translation/detect-language
Authorization: Bearer <jwt_token>
Content-Type: application/json

{
  "text": "Bonjour, comment allez-vous?"
}
```

## 🔌 WebSocket API

### Connection
```javascript
const ws = new WebSocket('wss://your-domain.com/ws/streaming-translation');
```

### Authentication
```json
{
  "type": "authenticate",
  "token": "your_jwt_token"
}
```

### Start Translation
```json
{
  "type": "start_translation",
  "source_language": "en",
  "target_language": "es",
  "voice": "es-ES-female-1"
}
```

### Stream Audio (Binary)
Send binary audio data directly to the WebSocket connection.

### Events Received
```json
// Transcribed text
{
  "type": "transcription_text",
  "session_id": "stream_trans_123",
  "text": "Hello, how are you?",
  "timestamp": 1634567890
}

// Translated text
{
  "type": "translation_text",
  "session_id": "stream_trans_123",
  "text": "Hola, ¿cómo estás?",
  "timestamp": 1634567890
}

// Translation complete
{
  "type": "translation_complete",
  "session_id": "stream_trans_123",
  "timestamp": 1634567890
}
```

## 🛠️ Configuration

### Environment Variables (.env.cloud)

```bash
# Lecto AI Translation Service
LECTO_AI_API_KEY=JAKBSJP-A2WMV50-N43CNV1-2F8X8EV
LECTO_AI_BASE_URL=https://api.lecto.ai/v1
LECTO_AI_ENABLED=true

# Maestra Speech-to-Text Service
MAESTRA_STT_URL=https://api.maestra.ai/v1/stt
MAESTRA_STT_ENABLED=true

# NoteGPT Text-to-Speech Service
NOTEGPT_TTS_URL=https://api.notegpt.io/v1/tts
NOTEGPT_TTS_ENABLED=true

# Streaming Translation Settings
STREAMING_TRANSLATION_ENABLED=true
STREAMING_TRANSLATION_BUFFER_SIZE=512
STREAMING_TRANSLATION_TIMEOUT=30000
```

## 🚀 Usage Examples

### JavaScript Client Example

```javascript
class StreamingTranslation {
  constructor(wsUrl, jwtToken) {
    this.ws = new WebSocket(wsUrl);
    this.jwtToken = jwtToken;
    this.sessionId = null;
    
    this.ws.onopen = () => {
      this.authenticate();
    };
    
    this.ws.onmessage = (event) => {
      if (event.data instanceof Blob) {
        // Handle translated audio
        this.playTranslatedAudio(event.data);
      } else {
        // Handle text messages
        const data = JSON.parse(event.data);
        this.handleMessage(data);
      }
    };
  }
  
  authenticate() {
    this.ws.send(JSON.stringify({
      type: 'authenticate',
      token: this.jwtToken
    }));
  }
  
  startTranslation(sourceLang, targetLang, voice) {
    this.ws.send(JSON.stringify({
      type: 'start_translation',
      source_language: sourceLang,
      target_language: targetLang,
      voice: voice
    }));
  }
  
  streamAudio(audioData) {
    if (this.sessionId) {
      this.ws.send(audioData);
    }
  }
  
  handleMessage(data) {
    switch (data.type) {
      case 'translation_started':
        this.sessionId = data.session_id;
        console.log('Translation session started:', this.sessionId);
        break;
        
      case 'transcription_text':
        console.log('Transcribed:', data.text);
        this.displayTranscription(data.text);
        break;
        
      case 'translation_text':
        console.log('Translated:', data.text);
        this.displayTranslation(data.text);
        break;
        
      case 'translation_complete':
        console.log('Translation session completed');
        this.sessionId = null;
        break;
    }
  }
  
  displayTranscription(text) {
    // Update UI with transcribed text
    document.getElementById('transcription').textContent = text;
  }
  
  displayTranslation(text) {
    // Update UI with translated text
    document.getElementById('translation').textContent = text;
  }
  
  playTranslatedAudio(audioBlob) {
    // Play translated audio
    const audio = new Audio(URL.createObjectURL(audioBlob));
    audio.play();
  }
}

// Usage
const translator = new StreamingTranslation(
  'wss://your-domain.com/ws/streaming-translation',
  'your_jwt_token'
);

// Start English to Spanish translation
translator.startTranslation('en', 'es', 'es-ES-female-1');

// Stream audio from microphone
navigator.mediaDevices.getUserMedia({ audio: true })
  .then(stream => {
    const mediaRecorder = new MediaRecorder(stream);
    
    mediaRecorder.ondataavailable = (event) => {
      if (event.data.size > 0) {
        translator.streamAudio(event.data);
      }
    };
    
    mediaRecorder.start(100); // Send chunks every 100ms
  });
```

### Erlang Server Usage

```erlang
% Start streaming translation services
{ok, _} = aethertalk_lecto_ai:start_link(),
{ok, _} = aethertalk_maestra_stt:start_link(),
{ok, _} = aethertalk_notegpt_tts:start_link(),
{ok, _} = aethertalk_streaming_translation:start_link(),

% Start a translation session
UserId = <<"user123">>,
SourceLang = <<"en">>,
TargetLang = <<"es">>,
Voice = <<"es-ES-female-1">>,
CallbackPid = self(),

{ok, SessionId} = aethertalk_streaming_translation:start_translation_session(
    UserId, SourceLang, TargetLang, Voice, CallbackPid),

% Stream audio data
AudioChunk = <<binary_audio_data>>,
aethertalk_streaming_translation:stream_audio_chunk(SessionId, AudioChunk),

% Handle translation events
receive
    {transcription_text, SessionId, Text} ->
        io:format("Transcribed: ~s~n", [Text]);
    {translation_text, SessionId, TranslatedText} ->
        io:format("Translated: ~s~n", [TranslatedText]);
    {translation_audio, SessionId, AudioData} ->
        io:format("Received translated audio: ~p bytes~n", [byte_size(AudioData)]);
    {translation_complete, SessionId} ->
        io:format("Translation session completed~n")
end,

% End session
aethertalk_streaming_translation:end_translation_session(SessionId).
```

## 🧪 Testing

### Comprehensive Test Suite

Run the streaming translation test suite:

```bash
./test_streaming_translation.sh
```

### Module Verification

Verify all modules are properly compiled:

```bash
./simple_module_test.erl
```

### Manual Testing

1. **Start the server**:
   ```bash
   rebar3 shell
   ```

2. **Test direct translation**:
   ```bash
   curl -X POST http://localhost:8080/api/v1/translation/text \
     -H "Authorization: Bearer YOUR_JWT_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"text":"Hello world","source_language":"en","target_language":"es"}'
   ```

3. **Test WebSocket connection**:
   ```javascript
   const ws = new WebSocket('ws://localhost:8080/ws/streaming-translation');
   ```

## 🔒 Security & Privacy

### User Privacy
- Translation is **opt-in only** - disabled by default
- Users have full control over when translation is active
- No audio/text is processed unless explicitly enabled
- User settings are stored securely in the database

### API Security
- All endpoints require JWT authentication
- Rate limiting on translation requests
- Input validation and sanitization
- Secure WebSocket connections

### Data Handling
- Audio data is processed in real-time and not stored
- Text translations are not logged or persisted
- User preferences are encrypted in the database
- API keys are properly masked in logs

## 🌟 Benefits

### For Users
- **Break Language Barriers**: Communicate with anyone, anywhere
- **Real-time Translation**: No delays in conversation flow
- **Full Control**: Choose when and how translation works
- **Multiple Options**: Text and/or voice output
- **125+ Languages**: Support for most world languages
- **High Quality**: Professional-grade translation and speech synthesis

### For Developers
- **Modular Architecture**: Easy to extend and maintain
- **Streaming Design**: Efficient real-time processing
- **Comprehensive API**: REST and WebSocket interfaces
- **Well Documented**: Complete guides and examples
- **Tested**: Comprehensive test suite included
- **Configurable**: Environment-based configuration

## 🚀 Deployment

### Production Checklist

1. ✅ **Service Configuration**
   - Lecto AI API key configured
   - Maestra STT service enabled
   - NoteGPT TTS service enabled

2. ✅ **Database Setup**
   - User translation settings table created
   - Proper indexes for performance
   - Migration scripts executed

3. ✅ **Module Compilation**
   - All translation modules compile successfully
   - No compilation warnings or errors
   - Function exports verified

4. ✅ **API Endpoints**
   - All REST endpoints functional
   - WebSocket handler operational
   - Authentication working

5. ✅ **Testing**
   - Unit tests passing
   - Integration tests successful
   - Performance tests completed

### Monitoring

Monitor these key metrics in production:

- Translation request volume
- Service response times (STT, Translation, TTS)
- WebSocket connection stability
- User adoption rates
- Error rates and types

## 🎉 Conclusion

AetherTalk's streaming translation system represents a significant advancement in real-time communication technology. By combining cutting-edge AI services with a user-centric design, we've created a system that truly breaks down language barriers while respecting user privacy and preferences.

The system is now **ready for production** and will enable users to communicate seamlessly across language boundaries in real-time conversations! 🌍🗣️

---

**Ready to connect the world through seamless communication!** 🚀