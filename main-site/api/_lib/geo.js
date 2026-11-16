/* Distance between two points on the earth, in metres. Haversine on the mean
   radius, which is off by well under a metre at the distances a check-in
   radius is about. */

const EARTH_RADIUS_METRES = 6371008.8;

export function distanceMetres(firstPoint, secondPoint) {
  const radiansPerDegree = Math.PI / 180;
  const latitudeDifference = (secondPoint.lat - firstPoint.lat) * radiansPerDegree;
  const longitudeDifference = (secondPoint.lng - firstPoint.lng) * radiansPerDegree;
  const haversine =
    Math.sin(latitudeDifference / 2) ** 2 +
    Math.cos(firstPoint.lat * radiansPerDegree) * Math.cos(secondPoint.lat * radiansPerDegree) *
      Math.sin(longitudeDifference / 2) ** 2;
  return 2 * EARTH_RADIUS_METRES * Math.asin(Math.min(1, Math.sqrt(haversine)));
}
