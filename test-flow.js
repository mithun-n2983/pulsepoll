import http from 'http';
import app from './server.js';

// Start server on a test port
const TEST_PORT = 5055;
const server = app.listen(TEST_PORT, async () => {
  console.log(`Test server running on port ${TEST_PORT}`);
  try {
    await runTests();
    console.log('ALL TESTS PASSED WITH ZERO ERRORS!');
    process.exit(0);
  } catch (err) {
    console.error('TEST FAILED:', err);
    process.exit(1);
  }
});

function request(method, path, body = null, headers = {}) {
  return new Promise((resolve, reject) => {
    const isAbsolute = path.startsWith('/health');
    const requestPath = isAbsolute ? path : `/api${path}`;

    const options = {
      hostname: '127.0.0.1',
      port: TEST_PORT,
      path: requestPath,
      method,
      headers: {
        'Content-Type': 'application/json',
        ...headers,
      },
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          resolve({ status: res.statusCode, body: json });
        } catch {
          resolve({ status: res.statusCode, body: data });
        }
      });
    });

    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

async function runTests() {
  console.log('\n--- 1. Testing Silent Health Wake-Up Ping (GET /health) ---');
  const healthRes = await request('GET', '/health');
  if (healthRes.status !== 200 || healthRes.body.status !== 'ok') {
    throw new Error(`Health ping failed: ${JSON.stringify(healthRes.body)}`);
  }
  console.log(`✓ Health endpoint returned HTTP 200 { status: "${healthRes.body.status}" }`);

  console.log('\n--- 2. Testing Professor Poll Creation with Custom Thank You Message & Required Toggles ---');
  const createRes = await request('POST', '/admin/polls', {
    title: 'Kinematics & Microcontrollers Lecture Check',
    description: 'Autonomous robotics feedback check',
    thank_you_message: 'Outstanding job today! Check GitHub for the lab starter code.',
    type: 'poll',
    questions: [
      {
        type: 'mcq',
        title: 'Which motor driver is best for 12V 2A DC motors?',
        is_required: true,
        options: ['L298N', 'TB6612FNG', 'DRV8833', 'ULN2003'],
      },
      {
        type: 'rating',
        title: 'Rate today\'s lab pacing and instructions:',
        is_required: true,
      },
      {
        type: 'short_answer',
        title: 'Any doubts about PWM frequency or duty cycle? (Optional)',
        is_required: false,
      },
    ],
  }, { Authorization: 'Bearer mock-jwt-token' });

  if (createRes.status !== 201 || !createRes.body.success) {
    throw new Error(`Failed to create poll: ${JSON.stringify(createRes.body)}`);
  }

  const poll = createRes.body.poll;
  const joinCode = poll.join_code; // e.g., '351-253'
  const unhyphenatedCode = joinCode.replace('-', ''); // e.g., '351253'
  const pollId = poll.id;

  if (poll.thank_you_message !== 'Outstanding job today! Check GitHub for the lab starter code.') {
    throw new Error(`Custom thank you message not persisted: ${poll.thank_you_message}`);
  }

  console.log(`✓ Poll Created successfully! ID: ${pollId}, Join Code: ${joinCode}, Slug: ${unhyphenatedCode}`);
  console.log(`✓ Custom Thank You Message persisted: "${poll.thank_you_message}"`);

  console.log('\n--- 3. Testing Anonymous Fetch by Unhyphenated Slug (/api/polls/351253) ---');
  const fetchBySlugRes = await request('GET', `/polls/${unhyphenatedCode}`);
  if (fetchBySlugRes.status !== 200 || !fetchBySlugRes.body.success) {
    throw new Error(`Failed to fetch by unhyphenated slug ${unhyphenatedCode}: ${JSON.stringify(fetchBySlugRes.body)}`);
  }
  const fetchedPoll = fetchBySlugRes.body.poll;
  const fetchedQuestions = fetchBySlugRes.body.questions;

  if (fetchedPoll.thank_you_message !== poll.thank_you_message) {
    throw new Error('Fetched poll missing thank_you_message');
  }
  if (!fetchedQuestions[0].is_required || !fetchedQuestions[1].is_required || fetchedQuestions[2].is_required) {
    throw new Error('Question is_required flags do not match');
  }

  console.log(`✓ Successfully retrieved poll by unhyphenated slug!`);
  console.log(`✓ Verified Q1 is_required: ${fetchedQuestions[0].is_required}`);
  console.log(`✓ Verified Q3 (optional) is_required: ${fetchedQuestions[2].is_required}`);

  const q1 = fetchedQuestions[0];
  const q2 = fetchedQuestions[1];

  console.log('\n--- 4. Testing Anonymous Submission with Optional Question left blank ---');
  const submitRes = await request('POST', `/polls/${unhyphenatedCode}/respond`, {
    answers: [
      { question_id: q1.id, option_id: q1.options[1].id },
      { question_id: q2.id, rating_value: 5 },
      // Optional Q3 is omitted!
    ],
  });
  if (submitRes.status !== 201 || !submitRes.body.success) {
    throw new Error(`Submission failed: ${JSON.stringify(submitRes.body)}`);
  }
  console.log(`✓ Anonymous Response recorded cleanly with optional question blank: ${submitRes.body.message}`);

  console.log('\n--- 5. Verifying Live Stats (/api/polls/:slug/stats) ---');
  const statsRes = await request('GET', `/polls/${unhyphenatedCode}/stats`);
  if (statsRes.status !== 200 || statsRes.body.total_responses < 1) {
    throw new Error(`Stats mismatch: ${JSON.stringify(statsRes.body)}`);
  }
  console.log(`✓ Live Stats show ${statsRes.body.total_responses} response(s) received!`);
}
