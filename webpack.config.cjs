const path = require('path');

module.exports = {
  mode: 'production',
  entry: './mediasoup-entry.js',
  output: {
    path: path.resolve(__dirname, 'public'),
    filename: 'mediasoup-client.js',
    library: {
      name: 'mediasoupClient',
      type: 'window'
    },
    globalObject: 'this'
  },
  resolve: {
    extensions: ['.js']
  }
};
