importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyA0YxkcePFqXJah5Om22ocaXSyCMzLz9NQ',
  authDomain: 'integra360-94704.firebaseapp.com',
  databaseURL: 'https://integra360-94704-default-rtdb.firebaseio.com',
  projectId: 'integra360-94704',
  storageBucket: 'integra360-94704.firebasestorage.app',
  messagingSenderId: '379551786878',
  appId: '1:379551786878:web:bfdce56a6b9454b984352f',
  measurementId: 'G-G74NMJWNSH',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  if (payload.notification) return;

  const title = payload.data?.title || 'Nueva notificacion';
  const body = payload.data?.body || 'Tienes una notificacion pendiente.';

  self.registration.showNotification(title, {
    body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: payload.data || {},
  });
});
