import { ApplicationError } from '../application/errors.js';

export const readBearerToken = (authorizationHeader: string | null | undefined): string | null => {
  if (!authorizationHeader) {
    return null;
  }

  const [scheme, token] = authorizationHeader.split(' ', 2);
  if (scheme !== 'Bearer' || !token || token.length === 0) {
    throw new ApplicationError('unauthorized', 'invalid_authorization_header');
  }

  return token;
};
