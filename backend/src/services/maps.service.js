/**
 * maps.service.js
 * Wrappers around Google Maps Geocoding API and Directions API.
 * Both functions return null (never throw) so callers can degrade gracefully.
 */

import { env } from '../config/env.js';

const GEOCODE_BASE      = 'https://maps.googleapis.com/maps/api/geocode/json';
const DIRECTIONS_BASE   = 'https://maps.googleapis.com/maps/api/directions/json';
const AUTOCOMPLETE_BASE = 'https://maps.googleapis.com/maps/api/place/autocomplete/json';

/**
 * Geocode a human-readable address string to { lat, lng }.
 * Returns null if the address cannot be resolved or if the API call fails.
 *
 * @param {string} address
 * @returns {Promise<{lat: number, lng: number} | null>}
 */
export async function geocodeAddress(address) {
  if (!address || typeof address !== 'string' || address.trim().length === 0) {
    return null;
  }

  const apiKey = env.googleMaps.apiKey;
  if (!apiKey) {
    console.warn('[maps.service] geocodeAddress: GOOGLE_MAPS_API_KEY is not configured');
    return null;
  }

  const url = `${GEOCODE_BASE}?address=${encodeURIComponent(address.trim())}&key=${apiKey}`;

  try {
    const res  = await fetch(url);
    const data = await res.json();

    if (data.status !== 'OK' || !data.results || data.results.length === 0) {
      console.warn(`[maps.service] geocodeAddress: status=${data.status} for address="${address}"`);
      return null;
    }

    const { lat, lng } = data.results[0].geometry.location;
    return { lat, lng };
  } catch (err) {
    console.error('[maps.service] geocodeAddress error:', err?.message || err);
    return null;
  }
}

/**
 * Get driving directions between two coordinate pairs.
 * Returns an object with duration, distance, and the encoded overview polyline.
 * Returns null if no route is found or if the API call fails.
 *
 * @param {number} originLat
 * @param {number} originLng
 * @param {number} destLat
 * @param {number} destLng
 * @returns {Promise<{
 *   duration_text: string,
 *   duration_seconds: number,
 *   distance_text: string,
 *   distance_meters: number,
 *   polyline: string
 * } | null>}
 */
export async function getDirections(originLat, originLng, destLat, destLng) {
  const apiKey = env.googleMaps.apiKey;
  if (!apiKey) {
    console.warn('[maps.service] getDirections: GOOGLE_MAPS_API_KEY is not configured');
    return null;
  }

  const url =
    `${DIRECTIONS_BASE}` +
    `?origin=${originLat},${originLng}` +
    `&destination=${destLat},${destLng}` +
    `&mode=driving` +
    `&key=${apiKey}`;

  try {
    const res  = await fetch(url);
    const data = await res.json();

    if (data.status === 'ZERO_RESULTS') {
      console.warn('[maps.service] getDirections: no route found between the given coordinates');
      return null;
    }

    if (data.status !== 'OK' || !data.routes || data.routes.length === 0) {
      console.warn(`[maps.service] getDirections: status=${data.status}`);
      return null;
    }

    const route = data.routes[0];
    const leg   = route.legs[0];

    return {
      duration_text:    leg.duration.text,
      duration_seconds: leg.duration.value,   // seconds
      distance_text:    leg.distance.text,
      distance_meters:  leg.distance.value,   // metres
      polyline:         route.overview_polyline.points, // encoded polyline string
    };
  } catch (err) {
    console.error('[maps.service] getDirections error:', err?.message || err);
    return null;
  }
}

/**
 * Get place autocomplete predictions for a partial address query.
 * Biased toward Pakistan by default (components=country:pk).
 *
 * @param {string} input  — partial address text typed by the user
 * @returns {Promise<Array<{description: string, place_id: string}>>} — up to 5 suggestions
 */
export async function getPlacesAutocomplete(input) {
  if (!input || typeof input !== 'string' || input.trim().length < 2) {
    return [];
  }

  const apiKey = env.googleMaps.apiKey;
  if (!apiKey) {
    console.warn('[maps.service] getPlacesAutocomplete: GOOGLE_MAPS_API_KEY is not configured');
    return [];
  }

  const url =
    `${AUTOCOMPLETE_BASE}` +
    `?input=${encodeURIComponent(input.trim())}` +
    `&components=country:pk` +
    `&language=en` +
    `&key=${apiKey}`;

  try {
    const res  = await fetch(url);
    const data = await res.json();

    if (data.status !== 'OK' && data.status !== 'ZERO_RESULTS') {
      console.warn(`[maps.service] getPlacesAutocomplete: status=${data.status}`);
      return [];
    }

    return (data.predictions || []).map((p) => ({
      description: p.description,
      place_id:    p.place_id,
    }));
  } catch (err) {
    console.error('[maps.service] getPlacesAutocomplete error:', err?.message || err);
    return [];
  }
}
