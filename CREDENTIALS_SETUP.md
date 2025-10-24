# 🔐 Credentials Setup Guide

## Overview

This guide explains how to set up the required credentials for AetherTalk's cloud services integration.

## 🚨 Security Notice

**NEVER commit actual credentials to version control!** All credential files are included in `.gitignore` to prevent accidental commits.

## 📋 Required Credentials

### 1. Environment Configuration

Copy the template and fill in your credentials:

```bash
cp .env.cloud.template .env.cloud
```

Edit `.env.cloud` with your actual credentials:

```bash
# Example values - replace with your actual credentials
DATABASE_URL=postgresql://user:pass@ep-example.us-east-1.aws.neon.tech:5432/aethertalk
REDIS_URL=redis://user:pass@redis-12345.c1.us-east-1-2.ec2.cloud.redislabs.com:12345
MEGA_EMAIL=your-email@example.com
MEGA_PASSWORD=your-mega-password
FIREBASE_PROJECT_ID=your-firebase-project
FIREBASE_API_KEY=AIzaSyExample...
LECTO_AI_API_KEY=JAKBSJP-Example...
```

### 2. Firebase Admin SDK

Copy the template and add your Firebase service account:

```bash
cp config/firebase-admin-sdk.json.template config/firebase-admin-sdk.json
```

Get your Firebase Admin SDK JSON from:
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Go to Project Settings → Service Accounts
4. Click "Generate new private key"
5. Download the JSON file
6. Replace the content of `config/firebase-admin-sdk.json`

## 🌐 Cloud Service Setup

### Neon PostgreSQL

1. Sign up at [Neon](https://neon.tech/)
2. Create a new project
3. Get connection string from dashboard
4. Add to `DATABASE_URL` in `.env.cloud`

### Redis Cloud

1. Sign up at [Redis Cloud](https://redis.com/redis-enterprise-cloud/)
2. Create a new database
3. Get connection details
4. Add to `REDIS_URL` in `.env.cloud`

### MEGA Storage

1. Create account at [MEGA](https://mega.nz/)
2. Use your login credentials
3. Add to `MEGA_EMAIL` and `MEGA_PASSWORD` in `.env.cloud`

### Firebase Authentication

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create new project or use existing
3. Enable Authentication → Phone
4. Get configuration from Project Settings
5. Download Admin SDK JSON
6. Add all values to `.env.cloud`

### Translation Services

#### Lecto AI
1. Sign up at [Lecto AI](https://lecto.ai/)
2. Get API key from dashboard
3. Add to `LECTO_AI_API_KEY` in `.env.cloud`

#### Maestra
1. Sign up at [Maestra](https://maestra.ai/)
2. Get API key from account settings
3. Add to `MAESTRA_API_KEY` in `.env.cloud`

#### NoteGPT
1. Sign up at [NoteGPT](https://notegpt.io/)
2. Get API key from settings
3. Add to `NOTEGPT_API_KEY` in `.env.cloud`

## 🔧 Verification

After setting up credentials, verify the configuration:

```bash
# Test cloud services
./test_cloud_services.sh

# Test Firebase integration
./test_firebase_integration.sh

# Test streaming translation
./test_streaming_translation.sh

# Run comprehensive tests
./comprehensive_test.sh
```

## 🚀 Production Deployment

### Environment Variables

For production deployment, set environment variables instead of using `.env.cloud`:

```bash
export DATABASE_URL="postgresql://..."
export REDIS_URL="redis://..."
export FIREBASE_PROJECT_ID="your-project"
# ... etc
```

### Docker Deployment

If using Docker, pass credentials as environment variables:

```bash
docker run -e DATABASE_URL="postgresql://..." \
           -e REDIS_URL="redis://..." \
           -e FIREBASE_PROJECT_ID="your-project" \
           -v /path/to/firebase-admin-sdk.json:/app/config/firebase-admin-sdk.json \
           aethertalk:latest
```

### Kubernetes Deployment

Use Kubernetes secrets for credential management:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: aethertalk-secrets
type: Opaque
stringData:
  database-url: "postgresql://..."
  redis-url: "redis://..."
  firebase-project-id: "your-project"
  # ... etc
```

## 🔒 Security Best Practices

### Credential Management

1. **Never commit credentials** to version control
2. **Use environment variables** in production
3. **Rotate credentials regularly**
4. **Use least privilege access**
5. **Monitor credential usage**

### File Permissions

Set proper permissions for credential files:

```bash
chmod 600 .env.cloud
chmod 600 config/firebase-admin-sdk.json
```

### Access Control

- Limit access to credential files
- Use service accounts with minimal permissions
- Enable audit logging for credential access
- Implement credential rotation policies

## 🆘 Troubleshooting

### Common Issues

#### Database Connection Failed
- Check connection string format
- Verify network access to database
- Confirm credentials are correct
- Test connection manually

#### Redis Connection Failed
- Verify Redis URL format
- Check Redis server status
- Confirm authentication credentials
- Test with Redis CLI

#### Firebase Authentication Failed
- Verify project ID matches
- Check API key is correct
- Ensure Admin SDK JSON is valid
- Confirm Firebase services are enabled

#### Translation Services Failed
- Verify API keys are active
- Check service quotas and limits
- Confirm service endpoints are accessible
- Test with service documentation

### Debug Mode

Enable debug logging to troubleshoot issues:

```bash
export LOG_LEVEL=debug
./start_aethertalk.sh
```

### Health Checks

Monitor service health:

```bash
# Check database connectivity
curl http://localhost:8080/health/database

# Check Redis connectivity  
curl http://localhost:8080/health/redis

# Check Firebase status
curl http://localhost:8080/health/firebase

# Check translation services
curl http://localhost:8080/health/translation
```

## 📞 Support

If you encounter issues:

1. Check the troubleshooting section above
2. Review service documentation
3. Check service status pages
4. Contact service support if needed

---

**Remember: Keep your credentials secure and never share them publicly!** 🔐