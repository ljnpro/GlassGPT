export type ApplicationErrorCode =
  | 'conflict'
  | 'forbidden'
  | 'invalid_request'
  | 'not_found'
  | 'server_error'
  | 'service_unavailable'
  | 'unauthorized';

export class ApplicationError extends Error {
  public readonly code: ApplicationErrorCode;

  public constructor(code: ApplicationErrorCode, message: string) {
    super(message);
    this.code = code;
    this.name = 'ApplicationError';
  }
}

export class InvalidAccessTokenError extends Error {
  public constructor(message: string) {
    super(message);
    this.name = 'InvalidAccessTokenError';
  }
}

export class InvalidAppleIdentityTokenError extends Error {
  public constructor(message: string) {
    super(message);
    this.name = 'InvalidAppleIdentityTokenError';
  }
}

export const isApplicationError = (error: unknown): error is ApplicationError => {
  return error instanceof ApplicationError;
};
