const int servoOnPin = 7, servoAnalogInPin = A1;
float posIs, posIsDeg,                 //pos in voltage values and pos in degrees
  posServo1 = 0, posServo2 = 90,       //angolo iniziale e finale
  posSensor1 = 540, posSensor2 = 145;  //corrispondente valore from the serial monitor

void setup() {
  Serial.begin(9600);
  while (!Serial);
  pinMode(servoOnPin, OUTPUT);
  digitalWrite(servoOnPin, HIGH);
}

void loop() {
  posIs = analogRead(servoAnalogInPin);
  posIsDeg = ((posServo2 - posServo1) / (posSensor2 - posSensor1)) * (posIs - posSensor1) + posServo1;  //Linear interpolation
  int posIsDeg = map(posIs, posSensor1, posSensor2, posServo1, posServo2);     //alternative way to implement the calibration. Does integer division so it not super precise
  //Serial.print("Position[deg] :");
  //Serial.println(posIsDeg);
  Serial.println(posIsDeg);
  delay(100);
}