import axios from 'axios';
import nutriplusAPI from '../nutriplus';
import ApiClient from '../ApiClient';

vi.mock('axios');

describe('#NutriplusAPI', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.history.pushState({}, '', '/app/accounts/42/conversations/189');
  });

  it('creates correct instance', () => {
    expect(nutriplusAPI).toBeInstanceOf(ApiClient);
    expect(nutriplusAPI).toHaveProperty('bootstrap');
  });

  it('requests a bootstrap token for the current account and conversation', async () => {
    const response = {
      data: { token: 'jwt-token', expires_in: 300 },
    };
    axios.post.mockResolvedValue(response);

    await expect(nutriplusAPI.bootstrap(189)).resolves.toEqual(response.data);

    expect(axios.post).toHaveBeenCalledWith(
      '/api/v1/accounts/42/nutriplus/bootstrap',
      { conversation_id: 189 }
    );
  });
});
