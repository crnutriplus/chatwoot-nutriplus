import axios from 'axios';
import ApiClient from './ApiClient';

class NutriplusAPI extends ApiClient {
  constructor() {
    super('nutriplus', { accountScoped: true });
  }

  bootstrap(conversationId) {
    return axios
      .post(`${this.url}/bootstrap`, { conversation_id: conversationId })
      .then(response => response.data);
  }
}

export default new NutriplusAPI();
