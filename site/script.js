// Generate a CSRF token and set it in the hidden input field
function generateCsrfToken() {
  const array = new Uint8Array(16);
  window.crypto.getRandomValues(array);
  return Array.from(array, byte => byte.toString(16).padStart(2, '0')).join('');
}

document.getElementById('csrfToken').value = generateCsrfToken();

// Ensure the print button is hidden initially
const printButton = document.getElementById('printButton');
printButton.style.display = 'none';

// Input sanitization function
function sanitizeInput(input) {
  const div = document.createElement('div');
  div.textContent = input;
  return div.innerHTML;
}

// Function to display messages
function displayMessage(type, text) {
  const messageElement = document.getElementById('message');
  messageElement.className = `message ${type}`;
  messageElement.textContent = text;
  messageElement.style.display = 'block';
}

// Function to calculate the SHA-256 hash of the QR code image data
async function calculateSHA256(blob) {
  const arrayBuffer = await blob.arrayBuffer();
  const hashBuffer = await crypto.subtle.digest('SHA-256', arrayBuffer);
  return btoa(String.fromCharCode(...new Uint8Array(hashBuffer)));
}

// Function to decode a base64-encoded string
function decodeBase64(base64String) {
  const binaryString = atob(base64String);
  const binaryArray = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    binaryArray[i] = binaryString.charCodeAt(i);
  }
  return binaryArray;
}

// Form submission handler
document.getElementById('qrForm').addEventListener('submit', async function(event) {
  event.preventDefault(); // Prevent the form from submitting traditionally

  // Sanitize inputs
  const textInput = sanitizeInput(document.getElementById('text').value);
  const marginInput = sanitizeInput(document.getElementById('margin').value);
  const sizeInput = sanitizeInput(document.getElementById('size').value);
  const dpiInput = sanitizeInput(document.getElementById('dpi').value);
  const ignorecaseInput = document.getElementById('ignorecase').checked ? 1 : 0;
  const logoInput = document.getElementById('logo').checked ? 1 : 0;
  const csrfToken = document.getElementById('csrfToken').value;

  // Validate inputs
  if (!textInput.trim()) {
    displayMessage('error', 'Text input cannot be empty.');
    return;
  }
  if (marginInput < 0) {
    displayMessage('error', 'Margin must be 0 or greater.');
    return;
  }
  if (sizeInput < 1) {
    displayMessage('error', 'Size must be 1 or greater.');
    return;
  }
  if (dpiInput < 72) {
    displayMessage('error', 'DPI must be 72 or greater.');
    return;
  }

  // Make a POST request to the server to generate the QR code
  const response = await fetch('/qr', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      text: textInput,
      margin: marginInput,
      size: sizeInput,
      dpi: dpiInput,
      ignorecase: ignorecaseInput,
      logo: logoInput,
      csrfToken: csrfToken
    })
  });

  if (response.ok) {
    const blob = await response.blob(); // Assume the server returns the QR code as an image blob
    const qrImageUrl = URL.createObjectURL(blob);

    // Verify the Content-Digest header if it exists
    const serverDigest = response.headers.get('Content-Digest');
    if (serverDigest) {
      // Ensure the Content-Digest header is in the correct format
      const digestMatch = serverDigest.match(/^sha-256=:([A-Za-z0-9+/=]+):$/);
      if (!digestMatch) {
        displayMessage('error', 'Invalid Content-Digest header format.');
        return;
      }

      // Decode the base64-encoded digest from the header
      const decodedServerDigest = decodeBase64(digestMatch[1]);

      // Calculate the SHA-256 hash of the blob
      const calculatedDigest = await calculateSHA256(blob);

      // Decode the calculated digest for comparison
      const decodedCalculatedDigest = decodeBase64(calculatedDigest);

      // Compare the decoded digests
      if (!compareUint8Arrays(decodedServerDigest, decodedCalculatedDigest)) {
        displayMessage('error', 'Content-Digest verification failed.');
        return;
      }
    }

    // Display the QR code image
    const qrImageElement = document.getElementById('qrCodeImage');
    qrImageElement.src = qrImageUrl;
    qrImageElement.parentElement.style.display = 'block';

    // Enable the download button
    const downloadButton = document.getElementById('downloadButton');
    downloadButton.href = qrImageUrl;
    downloadButton.style.display = 'inline-block';

    // Enable the print button
    const printButton = document.getElementById('printButton');
    printButton.style.display = 'inline-block';

    // Display success message
    displayMessage('success', 'QR Code generated successfully!');
  } else {
    displayMessage('error', 'Failed to generate QR code. Please try again.');
  }
});

// Function to compare two Uint8Array objects
function compareUint8Arrays(array1, array2) {
  if (array1.length !== array2.length) {
    return false;
  }
  for (let i = 0; i < array1.length; i++) {
    if (array1[i] !== array2[i]) {
      return false;
    }
  }
  return true;
}

document.getElementById('printButton').addEventListener('click', function () {
  const qrImageElement = document.getElementById('qrCodeImage');
  if (qrImageElement.src) {
    const printWindow = window.open('', '_blank');
    printWindow.document.write(`
      <html>
        <head>
          <title>Print QR Code</title>
        </head>
        <body style="display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0;">
          <img src="${qrImageElement.src}" style="max-width: 100%; height: auto; border: 1px solid #cccccc; border-radius: 4px;">
        </body>
      </html>
    `);
    printWindow.document.close();
    printWindow.print();
  } else {
    alert('Please generate a QR code before printing.');
  }
});