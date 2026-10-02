const test = require('node:test');
const assert = require('node:assert/strict');
const {createHmac} = require('node:crypto');

const {
  verifyMetaWebhookSignature,
  extractMetaDeliveryStatuses,
} = require('../lib/whatsapp_meta_webhook');

test('acepta solo el cuerpo original firmado por la app de Meta', () => {
  const secret = 'secreto-de-prueba';
  const body = Buffer.from('{"object":"whatsapp_business_account"}');
  const signature = `sha256=${createHmac('sha256', secret).update(body).digest('hex')}`;

  assert.equal(verifyMetaWebhookSignature(body, signature, secret), true);
  assert.equal(verifyMetaWebhookSignature(Buffer.from('{}'), signature, secret), false);
  assert.equal(verifyMetaWebhookSignature(body, signature, 'otro-secreto'), false);
  assert.equal(verifyMetaWebhookSignature(body, 'sha256=malformada', secret), false);
  assert.equal(verifyMetaWebhookSignature(body, signature, ''), false);
});

test('extrae el error de entrega y descarta datos ajenos al estado', () => {
  const statuses = extractMetaDeliveryStatuses({
    object: 'whatsapp_business_account',
    entry: [{
      id: 'waba-meta',
      changes: [{
        field: 'messages',
        value: {
          metadata: {phone_number_id: 'phone-meta'},
          statuses: [{
            id: 'wamid.123',
            status: 'failed',
            timestamp: '1790970000',
            recipient_id: '573001234567',
            errors: [{
              code: 131042,
              title: 'Business eligibility payment issue',
              error_data: {details: 'Payment method needs attention'},
            }],
          }],
        },
      }],
    }],
  });

  assert.deepEqual(statuses, [{
    messageId: 'wamid.123',
    status: 'failed',
    statusTimestamp: 1790970000,
    destinationLast4: '4567',
    errorCode: 131042,
    errorMessage: 'Business eligibility payment issue · Payment method needs attention',
  }]);
  assert.deepEqual(extractMetaDeliveryStatuses({object: 'not-whatsapp'}), []);
});
