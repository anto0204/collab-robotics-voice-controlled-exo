/*
  EduExo - WiFi AP + WebServer + Servo position commands + Minimum-Jerk + Stall Safety
  - AP WiFi (open)
  - Comandi ricevuti via TCP su porta 80 (anche stringhe tipo "yellow\n" o "GET /yellow HTTP/1.1")
  - Target fisico: 0..90 [deg]
  - Comando servo: target fisico + offset (clamp 0..180)
  - Feedback analogico su A1 -> deg (calibrazione lineare)
  - Traiettoria minimum-jerk (quintica) per passare al target senza step
  - Safety: stallo (errore grande + movimento quasi nullo per N cicli) + pulsanti detach/attach
*/

#include <SPI.h>
#include <WiFiNINA.h>
#include <Servo.h>
#include <math.h>

// ----------------- WiFi -----------------
char ssid[] = "Arduino Antonio";
int status = WL_IDLE_STATUS;
WiFiServer server(80);

// ----------------- Servo & IO -----------------
Servo myservo;
const int servoOnPin       = 7;
const int PWMPin           = 5;
const int servoAnalogInPin = A1;

const int buttonPinDetach  = 3;   // emergency detach
const int buttonPinAttach  = 2;   // reset safety + attach

// ----------------- ROM fisico -----------------
const float PHYS_MIN = 0.0f;     // [deg]
const float PHYS_MAX = 90.0f;    // [deg]

// Offset comando servo (calibralo bene)
float posOffset = 90.0f;         // [deg]

// ----------------- Encoder -> gradi (calibrazione lineare) -----------------
const float posServo1  = 0.0f;
const float posServo2  = 90.0f;
const float posSensor1 = 540.0f;
const float posSensor2 = 100.0f;

// ----------------- Controllo a tempo fisso -----------------
const uint16_t CTRL_HZ = 50;                    // 50 Hz
const uint32_t CTRL_DT_MS = 1000UL / CTRL_HZ;   // 20 ms
uint32_t lastCtrlMs = 0;

// Letture e filtraggio
float posIs = 0.0f;        // ADC raw
float posDeg = 0.0f;       // deg raw
float posDegFilt = 0.0f;   // deg filtrato
const float LPF_ALPHA = 0.2f; // 0..1

// ----------------- Target & Trajectory (minimum jerk) -----------------
float targetPhys = 0.0f;   // target fisico [deg] 0..90
float cmdPhys = 0.0f;      // comando fisico corrente [deg] (prima dell'offset)

// Traiettoria: q(t)=q0 + dq*(10s^3-15s^4+6s^5), s=t/T in [0,1]
bool  trajActive = false;
float traj_q0 = 0.0f;
float traj_qf = 0.0f;
uint32_t trajStartMs = 0;
uint32_t trajTms = 800;    // durata [ms], ricalcolata

// Limiti envelope per scegliere T (da tarare)
const float VMAX_DEG_S  = 60.0f;     // [deg/s]
const float AMAX_DEG_S2 = 250.0f;    // [deg/s^2]

// ----------------- Safety (stall detection) -----------------
volatile bool reqDetach = false;
volatile bool reqAttach = false;

bool safetyStop = false;
bool servoAttached = true;

float prevPosDegFilt = 0.0f;
uint16_t stillCount = 0;

const float ERR_TOL_DEG   = 5.0f;   // se errore > 5°, mi aspetto movimento
const float STILL_EPS_DEG = 0.4f;   // se movimento < 0.4°/tick -> quasi fermo
const uint16_t STILL_N    = 25;     // 25 ticks a 50 Hz => 0.5 s stallo

// ----------------- Prototipi -----------------
void printWiFiStatus();
void startMinimumJerkTo(float newTargetPhys);
float mapAdcToDeg(float adc);
float clampf(float x, float lo, float hi);
void handleClientNonBlocking();
void parseCommandLine(const String &line);
void updateControlStep();
void applyServoCommand(float physDeg);

// ISR (solo flag)
void isrDetach() { reqDetach = true; }
void isrAttach() { reqAttach = true; }

// ----------------- Setup -----------------
void setup() {
  Serial.begin(9600);
  while (!Serial) {}

  pinMode(servoOnPin, OUTPUT);
  digitalWrite(servoOnPin, HIGH);

  pinMode(buttonPinDetach, INPUT_PULLUP);
  pinMode(buttonPinAttach, INPUT_PULLUP);

  attachInterrupt(digitalPinToInterrupt(buttonPinDetach), isrDetach, FALLING);
  attachInterrupt(digitalPinToInterrupt(buttonPinAttach), isrAttach,  FALLING);

  myservo.attach(PWMPin);
  servoAttached = true;

  Serial.println("Access Point Web Server (AP open)");

  if (WiFi.status() == WL_NO_MODULE) {
    Serial.println("WiFi module failed.");
    while (true) {}
  }

  Serial.print("Creating AP: ");
  Serial.println(ssid);

  status = WiFi.beginAP(ssid);
  if (status != WL_AP_LISTENING) {
    Serial.println("AP creation failed.");
    while (true) {}
  }

  delay(1000);
  server.begin();
  printWiFiStatus();

  // init filtro posizione
  posIs = analogRead(servoAnalogInPin);
  posDeg = mapAdcToDeg(posIs);
  posDegFilt = posDeg;
  prevPosDegFilt = posDegFilt;

  // target iniziale
  targetPhys = clampf(0.0f, PHYS_MIN, PHYS_MAX);
  cmdPhys = targetPhys;
  startMinimumJerkTo(targetPhys);
}

// ----------------- Loop -----------------
void loop() {
  // 1) rete: non deve bloccare
  handleClientNonBlocking();

  // 2) pulsanti (fuori ISR)
  if (reqDetach) {
    reqDetach = false;
    if (servoAttached) {
      myservo.detach();
      servoAttached = false;
    }
    safetyStop = true;
    Serial.println("EMERGENCY DETACH -> safetyStop=TRUE");
  }

  if (reqAttach) {
    reqAttach = false;
    if (!servoAttached) {
      myservo.attach(PWMPin);
      servoAttached = true;
    }
    safetyStop = false;   // reset safety
    stillCount = 0;
    Serial.println("ATTACH + safety reset -> safetyStop=FALSE");
    startMinimumJerkTo(targetPhys); // riparti verso target corrente
  }

  // 3) controllo a tempo fisso
  uint32_t now = millis();
  if (now - lastCtrlMs >= CTRL_DT_MS) {
    lastCtrlMs = now;
    updateControlStep();
  }
}

// ----------------- Networking -----------------
void handleClientNonBlocking() {
  WiFiClient client = server.available();
  if (!client) return;

  client.setTimeout(30);

  // Leggi una linea (raw o HTTP)
  String line = client.readStringUntil('\n');
  line.trim();
  if (line.length() > 0) {
    Serial.print("RX: ");
    Serial.println(line);
    parseCommandLine(line);
  }

  client.println("OK");
  client.stop();
}

void parseCommandLine(const String &line) {
  String s = line;
  s.toLowerCase();

  auto has = [&](const char *kw) -> bool {
    return s.indexOf(kw) >= 0;
  };

  if (safetyStop) {
    // in safetyStop ignoro i comandi di moto
    if (has("attach") || has("reset")) {
      if (!servoAttached) { myservo.attach(PWMPin); servoAttached = true; }
      safetyStop = false;
      stillCount = 0;
      startMinimumJerkTo(targetPhys);
      Serial.println("Remote reset -> safetyStop=FALSE");
    } else {
      Serial.println("Ignored command (safetyStop=TRUE)");
    }
    return;
  }

  if (has("yellow")) {
    targetPhys = 0.0f;
    startMinimumJerkTo(targetPhys);
  } else if (has("blue")) {
    targetPhys = 45.0f;
    startMinimumJerkTo(targetPhys);
  } else if (has("green")) {
    targetPhys = 90.0f;
    startMinimumJerkTo(targetPhys);
  } else if (has("up")) {
    targetPhys = clampf(targetPhys + 5.0f, PHYS_MIN, PHYS_MAX);
    startMinimumJerkTo(targetPhys);
  } else if (has("down")) {
    targetPhys = clampf(targetPhys - 5.0f, PHYS_MIN, PHYS_MAX);
    startMinimumJerkTo(targetPhys);
  } else if (has("stop")) {
    targetPhys = clampf(posDegFilt, PHYS_MIN, PHYS_MAX);
    startMinimumJerkTo(targetPhys);
  }
}

// ----------------- Control step -----------------
void updateControlStep() {
  // 1) misura posizione
  posIs = analogRead(servoAnalogInPin);
  posDeg = mapAdcToDeg(posIs);

  // filtro LPF
  posDegFilt = (1.0f - LPF_ALPHA) * posDegFilt + LPF_ALPHA * posDeg;

  // per stampare SOLO durante la traiettoria (incluso ultimo tick)
  bool wasTrajActive = trajActive;

  // 2) aggiorna traiettoria
  if (trajActive) {
    uint32_t now = millis();
    uint32_t dt = now - trajStartMs;

    float s = (trajTms > 0) ? (float)dt / (float)trajTms : 1.0f;
    if (s >= 1.0f) {
      s = 1.0f;
      trajActive = false;
    }
    if (s < 0.0f) s = 0.0f;

    float s2 = s * s;
    float s3 = s2 * s;
    float s4 = s3 * s;
    float s5 = s4 * s;

    float blend = 10.0f*s3 - 15.0f*s4 + 6.0f*s5;
    cmdPhys = traj_q0 + (traj_qf - traj_q0) * blend;
  } else {
    cmdPhys = clampf(targetPhys, PHYS_MIN, PHYS_MAX);
  }

  // 3) safety stallo
  float err = fabs(cmdPhys - posDegFilt);
  float dpos = fabs(posDegFilt - prevPosDegFilt);
  prevPosDegFilt = posDegFilt;

  if (!safetyStop && servoAttached) {
    if (err > ERR_TOL_DEG && dpos < STILL_EPS_DEG) {
      stillCount++;
    } else {
      stillCount = 0;
    }

    if (stillCount >= STILL_N) {
      safetyStop = true;
      myservo.detach();
      servoAttached = false;
      Serial.print("SAFETY STOP (STALL) posDeg=");
      Serial.print(posDegFilt);
      Serial.print(" cmdPhys=");
      Serial.print(cmdPhys);
      Serial.print(" err=");
      Serial.println(err);
      return;
    }
  }

  // 4) applica comando servo
  if (!safetyStop && servoAttached) {
    applyServoCommand(cmdPhys);
  }

  // 5) stampa SOLO durante esecuzione traiettoria
  if (wasTrajActive) {
    uint32_t tNow = millis();
    Serial.print(tNow);
    Serial.print(",");
    Serial.println(posDegFilt); // o posDeg se vuoi il raw
  }
}

void applyServoCommand(float physDeg) {
  float phys = clampf(physDeg, PHYS_MIN, PHYS_MAX);

  float servoCmd = phys + posOffset;
  servoCmd = clampf(servoCmd, 0.0f, 180.0f);

  myservo.write((int)(servoCmd + 0.5f));
}

// ----------------- Trajectory start -----------------
void startMinimumJerkTo(float newTargetPhys) {
  newTargetPhys = clampf(newTargetPhys, PHYS_MIN, PHYS_MAX);

  traj_q0 = clampf(posDegFilt, PHYS_MIN, PHYS_MAX);
  traj_qf = newTargetPhys;

  float dq = fabs(traj_qf - traj_q0);

  float T1 = (VMAX_DEG_S > 1e-6f) ? (1.875f * dq / VMAX_DEG_S) : 0.8f;
  float T2 = (AMAX_DEG_S2 > 1e-6f) ? sqrtf(5.7735f * dq / AMAX_DEG_S2) : 0.8f;

  float T = T1;
  if (T2 > T) T = T2;

  if (T < 0.35f) T = 0.35f;
  if (T > 2.50f) T = 2.50f;
  T *= 1.25f;

  trajTms = (uint32_t)(T * 1000.0f);
  trajStartMs = millis();
  trajActive = true;

  targetPhys = newTargetPhys;

  Serial.print("New traj: q0=");
  Serial.print(traj_q0);
  Serial.print(" qf=");
  Serial.print(traj_qf);
  Serial.print(" Tms=");
  Serial.println(trajTms);
}

// ----------------- Utils -----------------
float mapAdcToDeg(float adc) {
  float denom = (posSensor2 - posSensor1);
  if (fabs(denom) < 1e-6f) return 0.0f;
  return (adc - posSensor1) * (posServo2 - posServo1) / denom + posServo1;
}

float clampf(float x, float lo, float hi) {
  if (x < lo) return lo;
  if (x > hi) return hi;
  return x;
}

void printWiFiStatus() {
  Serial.print("SSID: ");
  Serial.println(WiFi.SSID());

  IPAddress ip = WiFi.localIP();
  Serial.print("IP: ");
  Serial.println(ip);
}
