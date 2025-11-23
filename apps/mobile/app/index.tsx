/**
 * Root Index Route
 *
 * Redirects to the capture tab as the default route
 */

import { Redirect } from 'expo-router';

export default function Index() {
  return <Redirect href="/(tabs)/capture" />;
}

